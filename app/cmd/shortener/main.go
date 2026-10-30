// shortener: the platform's sample workload, a small URL shortener with the things a
// production service needs (metrics, traces, structured logs, probes, graceful
// shutdown), so the platform has something real to deploy, observe and break.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"github.com/Mohamed-H-Essa/k8s_platform_bootstrap/app/internal/shortener"
)

// version is set at build time: -ldflags "-X main.version=<git sha>"
var version = "dev"

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("service", "shortener", "version", version)
	if err := run(log); err != nil {
		log.Error("exit", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	shutdownTracing, err := shortener.SetupTracing(ctx, "shortener", version)
	if err != nil {
		return err
	}

	var store shortener.Store = shortener.NewMemory()
	if dsn := os.Getenv("DATABASE_URL"); dsn != "" {
		pg, err := connectWithRetry(ctx, log, dsn)
		if err != nil {
			return err
		}
		defer pg.Close()
		store = pg
	} else {
		log.Warn("DATABASE_URL not set: using the in-memory store")
	}

	reg := prometheus.NewRegistry()
	reg.MustRegister(collectors.NewGoCollector(), collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}))
	srv := &shortener.Server{
		Store:   store,
		Metrics: shortener.NewMetrics(reg),
		Log:     log,
		BaseURL: env("BASE_URL", "http://localhost:8080"),
		Fault: shortener.Fault{
			ErrorRate:    envFloat("FAULT_ERROR_RATE", 0),
			ExtraLatency: envDuration("FAULT_EXTRA_LATENCY", 0),
		},
	}
	if srv.Fault != (shortener.Fault{}) {
		log.Warn("fault injection is ON", "error_rate", srv.Fault.ErrorRate, "extra_latency", srv.Fault.ExtraLatency.String())
	}

	public := &http.Server{
		Addr:              env("ADDR", ":8080"),
		Handler:           otelhttp.NewHandler(srv.Routes(), "http", otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string { return r.Method + " " + r.Pattern })),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	admin := &http.Server{
		Addr:              env("ADMIN_ADDR", ":9090"),
		Handler:           srv.AdminRoutes(promhttp.HandlerFor(reg, promhttp.HandlerOpts{EnableOpenMetrics: true})),
		ReadHeaderTimeout: 5 * time.Second,
	}

	errs := make(chan error, 2)
	for _, s := range []*http.Server{public, admin} {
		go func() {
			if err := s.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
				errs <- err
			}
		}()
	}
	srv.SetReady(true)
	log.Info("listening", "addr", public.Addr, "admin", admin.Addr)

	select {
	case err := <-errs:
		return err
	case <-ctx.Done():
	}

	// Graceful shutdown: go unready first so the endpoint controller and the ingress stop
	// sending new requests, give them a moment to notice, then finish what's in flight.
	log.Info("shutting down")
	srv.SetReady(false)
	time.Sleep(envDuration("SHUTDOWN_DRAIN", 5*time.Second))
	sctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	_ = public.Shutdown(sctx)
	_ = admin.Shutdown(sctx)
	return shutdownTracing(sctx)
}

// connectWithRetry waits for Postgres at start-up (the database may still be electing a
// primary when the pod starts), backing off up to ~1 minute before giving up.
func connectWithRetry(ctx context.Context, log *slog.Logger, dsn string) (*shortener.Postgres, error) {
	wait := time.Second
	for attempt := 1; ; attempt++ {
		cctx, cancel := context.WithTimeout(ctx, 5*time.Second)
		pg, err := shortener.NewPostgres(cctx, dsn)
		cancel()
		if err == nil {
			return pg, nil
		}
		if attempt == 8 || ctx.Err() != nil {
			return nil, err
		}
		log.Warn("postgres not ready, retrying", "attempt", attempt, "in", wait.String(), "err", err)
		time.Sleep(wait)
		wait = min(wait*2, 15*time.Second)
	}
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func envFloat(k string, def float64) float64 {
	if f, err := strconv.ParseFloat(os.Getenv(k), 64); err == nil {
		return f
	}
	return def
}

func envDuration(k string, def time.Duration) time.Duration {
	if d, err := time.ParseDuration(os.Getenv(k)); err == nil {
		return d
	}
	return def
}
