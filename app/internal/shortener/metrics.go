package shortener

import (
	"net/http"
	"strconv"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"go.opentelemetry.io/otel/trace"
)

// The two SLIs live here (see platform/observability/slo-rules.yaml):
//
//	availability = requests without a 5xx / all requests
//	latency      = requests answered within 300 ms / all requests
//
// so 0.3 must stay a bucket boundary.
var latencyBuckets = []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2.5}

// Metrics holds the service's Prometheus collectors.
type Metrics struct {
	requests *prometheus.CounterVec
	duration *prometheus.HistogramVec
	created  prometheus.Counter
}

func NewMetrics(reg prometheus.Registerer) *Metrics {
	m := &Metrics{
		requests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "shortener_http_requests_total",
			Help: "HTTP requests by route, method and status code.",
		}, []string{"route", "method", "code"}),
		duration: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Name:    "shortener_http_request_duration_seconds",
			Help:    "HTTP request latency by route and method.",
			Buckets: latencyBuckets,
		}, []string{"route", "method"}),
		created: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "shortener_links_created_total",
			Help: "Links created.",
		}),
	}
	reg.MustRegister(m.requests, m.duration, m.created)
	return m
}

type statusWriter struct {
	http.ResponseWriter
	code int
}

func (w *statusWriter) WriteHeader(code int) { w.code = code; w.ResponseWriter.WriteHeader(code) }

// Instrument records a request under a fixed route label (never the raw path, so a
// flood of random codes can't explode the series count). Latency samples carry the
// trace id as an exemplar, which lets Grafana jump from a slow bucket to its trace.
func (m *Metrics) Instrument(route string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, code: http.StatusOK}
		next.ServeHTTP(sw, r)
		elapsed := time.Since(start).Seconds()

		m.requests.WithLabelValues(route, r.Method, strconv.Itoa(sw.code)).Inc()
		obs := m.duration.WithLabelValues(route, r.Method)
		if sc := trace.SpanContextFromContext(r.Context()); sc.IsSampled() {
			if eo, ok := obs.(prometheus.ExemplarObserver); ok {
				eo.ObserveWithExemplar(elapsed, prometheus.Labels{"trace_id": sc.TraceID().String()})
				return
			}
		}
		obs.Observe(elapsed)
	})
}
