package shortener

import (
	"encoding/json"
	"errors"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"net/url"
	"sync/atomic"
	"time"

	"go.opentelemetry.io/otel/trace"
)

// Fault is a deliberate, documented chaos hook: the chaos-day "bad release" sets
// FAULT_ERROR_RATE through GitOps, and rolling back is a git revert. Zero by default.
type Fault struct {
	ErrorRate    float64       // share of redirects answered with a 500
	ExtraLatency time.Duration // added to every redirect
}

// Server is the HTTP API.
type Server struct {
	Store   Store
	Metrics *Metrics
	Log     *slog.Logger
	BaseURL string // public origin for short links, e.g. http://sho.localtest.me
	Fault   Fault
	ready   atomic.Bool
}

// SetReady flips /readyz; it goes false first on shutdown so the endpoints drain.
func (s *Server) SetReady(v bool) { s.ready.Store(v) }

// Routes wires the API. Every route is instrumented under a fixed label.
func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.Handle("POST /api/links", s.Metrics.Instrument("create", http.HandlerFunc(s.create)))
	mux.Handle("GET /api/links/{code}", s.Metrics.Instrument("stats", http.HandlerFunc(s.stats)))
	mux.Handle("GET /{code}", s.Metrics.Instrument("redirect", http.HandlerFunc(s.redirect)))
	return mux
}

// AdminRoutes serves probes and metrics on a separate port that the Ingress never
// exposes. /readyz does not ping the database on purpose: if Postgres fails over,
// every pod would go unready together and the Service would empty; instead requests
// fail fast with 503 and recover the moment the new primary is up.
func (s *Server) AdminRoutes(metrics http.Handler) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /livez", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		if !s.ready.Load() {
			http.Error(w, "not ready", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	})
	mux.Handle("GET /metrics", metrics)
	return mux
}

func (s *Server) create(w http.ResponseWriter, r *http.Request) {
	var in struct {
		URL string `json:"url"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&in); err != nil {
		s.fail(w, r, http.StatusBadRequest, "body must be JSON: {\"url\": \"https://…\"}", nil)
		return
	}
	if u, err := url.ParseRequestURI(in.URL); err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" || len(in.URL) > 2048 {
		s.fail(w, r, http.StatusBadRequest, "url must be an absolute http(s) URL up to 2048 characters", nil)
		return
	}
	for attempt := 0; attempt < 3; attempt++ {
		code, err := NewCode()
		if err != nil {
			s.fail(w, r, http.StatusInternalServerError, "could not make a code", err)
			return
		}
		link, err := s.Store.Create(r.Context(), code, in.URL)
		if errors.Is(err, ErrConflict) {
			continue
		}
		if err != nil {
			s.fail(w, r, http.StatusServiceUnavailable, "storage unavailable", err)
			return
		}
		s.Metrics.created.Inc()
		writeJSON(w, http.StatusCreated, map[string]any{"code": link.Code, "url": link.URL, "short_url": s.BaseURL + "/" + link.Code})
		return
	}
	s.fail(w, r, http.StatusInternalServerError, "no free code after 3 tries", nil)
}

func (s *Server) redirect(w http.ResponseWriter, r *http.Request) {
	code := r.PathValue("code")
	if !ValidCode(code) {
		http.NotFound(w, r)
		return
	}
	if s.Fault.ExtraLatency > 0 {
		time.Sleep(s.Fault.ExtraLatency)
	}
	if s.Fault.ErrorRate > 0 && rand.Float64() < s.Fault.ErrorRate {
		s.fail(w, r, http.StatusInternalServerError, "injected fault", errors.New("FAULT_ERROR_RATE"))
		return
	}
	target, err := s.Store.Resolve(r.Context(), code)
	switch {
	case errors.Is(err, ErrNotFound):
		http.NotFound(w, r)
	case err != nil:
		s.fail(w, r, http.StatusServiceUnavailable, "storage unavailable", err)
	default:
		http.Redirect(w, r, target, http.StatusFound)
	}
}

func (s *Server) stats(w http.ResponseWriter, r *http.Request) {
	code := r.PathValue("code")
	if !ValidCode(code) {
		http.NotFound(w, r)
		return
	}
	link, err := s.Store.Get(r.Context(), code)
	switch {
	case errors.Is(err, ErrNotFound):
		http.NotFound(w, r)
	case err != nil:
		s.fail(w, r, http.StatusServiceUnavailable, "storage unavailable", err)
	default:
		writeJSON(w, http.StatusOK, link)
	}
}

// fail answers with a JSON error and logs it with the trace id, so a log line in Loki
// links straight to its trace in Tempo.
func (s *Server) fail(w http.ResponseWriter, r *http.Request, code int, msg string, err error) {
	if code >= 500 {
		sc := trace.SpanContextFromContext(r.Context())
		s.Log.ErrorContext(r.Context(), msg, "status", code, "path", r.URL.Path, "err", err, "trace_id", sc.TraceID().String())
	}
	writeJSON(w, code, map[string]string{"error": msg})
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}
