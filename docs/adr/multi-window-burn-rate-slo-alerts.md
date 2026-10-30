# SLOs with multi-window, multi-burn-rate alerts

**Status:** accepted

## Context
Alerts should fire when users are hurt enough to matter, and stay quiet otherwise. Threshold
alerts on causes (CPU, pod restarts) or on a raw error rate are either noisy or slow, and say
nothing about how much unreliability is acceptable.

## Decision
- Two SLOs for the shortener over 30 days, measured from the service's own metrics:
  - **availability**: 99.5 % of requests answer without a 5xx (error budget 0.5 %);
  - **latency**: 95 % of requests answer within 300 ms (the `le="0.3"` histogram bucket).
- Recording rules compute the error ratio over 5 m, 30 m, 1 h and 6 h for each SLO.
- Alerts follow the Google SRE Workbook (chapter 5):
  - **page** when the 1 h **and** the 5 m ratios exceed 14.4× the budget (2 % of the month's
    budget spent in an hour);
  - **ticket** when the 6 h **and** the 30 m ratios exceed 6× (5 % in six hours).
- Each alert links to its runbook (`docs/runbooks/slo-burn.md`).

## Alternatives
- **Static thresholds** ("error rate > 5 % for 5 minutes"): no link to a budget; either pages on
  blips or misses slow burns.
- **One window per alert**: a long window is slow to fire and slow to clear; a short one is noisy.
  Requiring both is what makes the alert precise and quick to reset.
- **Sloth or Pyrra** to generate the rules: the right call for many services. Here the rules are
  written by hand so each line can be explained.

## Consequences
- Time to detect depends on how bad things are. The long window must cross 14.4× the budget
  (7.2 % errors for availability), so with an error ratio *r* and a clean hour before it, the page
  needs about `60 min × 0.072 / r` plus the `for: 1m`. A total outage pages in minutes; a 10 %
  error rate takes much longer. Chaos day measures it.
- The SLI is measured at the service. Failures that never reach it (the gateway answering 503
  because no backend is ready) are not counted; the k6 client view on chaos day shows the gap.
