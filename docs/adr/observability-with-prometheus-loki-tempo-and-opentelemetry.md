# Observability: Prometheus, Loki, Tempo and OpenTelemetry

**Status:** accepted

## Context
During an incident you go from "something is wrong" (a metric) to "which request" (a trace) to
"what did it say" (a log line) in a few clicks. All of it has to fit next to everything else in
8 GB, and the workload should not be tied to one vendor's SDK.

## Decision
- **Metrics:** kube-prometheus-stack (Prometheus Operator, Prometheus, Alertmanager, Grafana,
  kube-state-metrics, node-exporter). Workloads bring their own `ServiceMonitor`/`PodMonitor` and
  `PrometheusRule`. Exemplar storage is on, so latency samples carry a `trace_id`.
- **Traces:** the app uses the OpenTelemetry SDK and sends OTLP/HTTP to an **OpenTelemetry
  Collector**, which forwards to **Tempo**. Apps only know "the collector", so the backend can
  change without touching them. Sampling is parent-based, 20 %.
- **Logs:** the app logs JSON (`log/slog`), with `trace_id` on errors. **Grafana Alloy** runs on
  every node, tails pod logs through the Kubernetes API and ships them to **Loki** (single binary,
  filesystem storage, 24 h retention).
- **Grafana** ties them together: an exemplar opens its trace in Tempo, a `trace_id` in a log line
  opens the trace, a trace links back to its logs.

## Alternatives
- **ELK / OpenSearch**: heavier (JVM), and logs only.
- **Jaeger** for traces: fine; Tempo stores traces in object storage without an index and sits in
  the same Grafana as everything else.
- **Promtail** for logs: deprecated in favour of Alloy.
- **A hosted vendor**: not available offline, and the point is to show how the parts fit.

## Consequences
- Loki, Tempo and Prometheus keep data on local volumes for a day or a few days; this is a lab,
  not a long-term store. On AWS they would write to S3.
- Metrics, traces and logs are separate pipelines; the collector could take metrics and logs too
  if the app moved to OTLP for everything.
