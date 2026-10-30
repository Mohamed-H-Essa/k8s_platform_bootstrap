package shortener

import (
	"context"
	"testing"
)

// The exporter is built but never reached: this only checks that the tracer provider
// can be set up with an endpoint configured (a resource/semconv mismatch broke it once).
func TestSetupTracingWithEndpoint(t *testing.T) {
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://127.0.0.1:1")
	shutdown, err := SetupTracing(context.Background(), "shortener", "test")
	if err != nil {
		t.Fatalf("SetupTracing: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel() // don't wait for the unreachable collector
	_ = shutdown(ctx)
}
