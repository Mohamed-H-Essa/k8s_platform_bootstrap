# Service level objectives: the shortener

Rules: [`platform/observability/slo-rules.yaml`](../platform/observability/slo-rules.yaml).
Dashboard: Grafana → **Shortener · service and SLOs**. Why this design:
[ADR](adr/multi-window-burn-rate-slo-alerts.md).

## The objectives (30-day window)

| SLO | SLI (good events / all events) | Objective | Error budget |
|---|---|---|---|
| Availability | requests that did not answer 5xx | 99.5 % | 0.5 % ≈ 3 h 36 min of total outage per 30 days |
| Latency | requests answered within 300 ms | 95 % | 5 % of requests may be slower |

Both are measured from the service's own metric, at the pod:

```promql
# availability: share of requests that failed
sum(rate(shortener_http_requests_total{code=~"5.."}[1h]))
  / sum(rate(shortener_http_requests_total[1h]))

# latency: share of requests slower than 300 ms (the le="0.3" bucket)
1 - sum(rate(shortener_http_request_duration_seconds_bucket{le="0.3"}[1h]))
  / sum(rate(shortener_http_request_duration_seconds_count[1h]))
```

The `route` label is fixed (`create`, `redirect`, `stats`), never the raw path, so random short
codes cannot explode the number of series.

## Recording rules
`slo:sli_error:ratio_rate{5m,30m,1h,6h}` with label `slo="availability"` or `slo="latency"`, and
`slo:error_budget:ratio` (0.005 and 0.05). Dashboards and alerts divide one by the other: that
ratio is the **burn rate** (1 = spending the budget exactly over 30 days).

## Alerts

| Alert | Fires when | Budget spent by then | Severity |
|---|---|---|---|
| `ShortenerErrorBudgetFastBurn` | 1 h **and** 5 m burn rate > 14.4, for 1 m | 2 % in 1 h | page |
| `ShortenerErrorBudgetSlowBurn` | 6 h **and** 30 m burn rate > 6, for 5 m | 5 % in 6 h | ticket |

The long window proves the problem is real; the short window proves it is still happening, so
the alert clears within minutes of the fix instead of an hour later.

**Time to detect.** For availability the 1 h ratio must pass 7.2 %. With an error ratio *r* that
starts after a clean hour, that takes about `60 min × 0.072 / r`, plus one minute of `for`, plus
up to a minute of scrape and evaluation delay. `scripts/chaos/bad-release.sh` measures it; it has
not run yet (see the [postmortem](postmortems/2026-10-30-chaos-day.md)). Chaos day also showed the
other side: a 6-minute outage at 48 % errors would not page at all, because over an hour it stays
under 7.2 %.

## What the SLI does not see
- Requests that never reach a pod: Envoy answering 503 because no backend is ready, or a client
  timing out on a dead node. The k6 client view on chaos day measures those separately.
- Correctness: a 302 to the wrong URL counts as good. `make smoke` checks correctness end to end.

## Error budget policy (what the numbers are for)
- Budget left: ship as usual.
- Fast-burn page: stop releases, follow the [runbook](runbooks/slo-burn.md), roll back first.
- Budget exhausted for the window: only reliability fixes until it recovers.
