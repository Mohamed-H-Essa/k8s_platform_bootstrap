# Runbook: shortener error budget burn

Alerts: `ShortenerErrorBudgetFastBurn` (page), `ShortenerErrorBudgetSlowBurn` (ticket).
Label `slo` says which objective: `availability` (5xx) or `latency` (> 300 ms). Background:
[docs/slo.md](../slo.md).

## 1. Look (2 minutes)
1. Grafana → **Shortener · service and SLOs** (http://grafana.localtest.me).
   - *Requests per second* by route and code: which route fails, since when?
   - *Availability burn rate*: is the 5 m line still above 14.4 (still happening) or falling?
   - *Errors* panel (Loki): the error messages; click a `trace_id` to open the trace in Tempo.
2. What changed? Releases are commits:
   ```bash
   argocd app history shortener        # or: git log --oneline -5 -- platform/workloads/shortener
   kubectl -n shortener rollout history deploy/shortener
   ```
3. Is it the database?
   ```bash
   kubectl -n shortener get clusters.postgresql.cnpg.io shortener-db   # phase, primary, ready
   kubectl -n shortener logs deploy/shortener | grep -i postgres | tail
   ```

## 2. Mitigate (roll back first, debug later)
- **A recent release:** revert it in Git and publish. Argo CD rolls the previous version out.
  ```bash
  git revert --no-edit <release-commit>
  make publish
  kubectl -n shortener rollout status deploy/shortener
  ```
  Do not `kubectl edit` or `kubectl rollout undo`: Argo CD's self-heal would put the bad version
  straight back. Git is the only way to change what runs.
- **Database failover in progress:** wait. CloudNativePG promotes the replica on its own; see
  [database-failover.md](database-failover.md). Requests fail fast with 503 until it is done.
- **Not enough capacity** (latency SLO, CPU at the limit): the HPA scales 2 → 6 pods. If it is at 6,
  raise `maxReplicas` in Git.
- **A node is gone:** pods leave it after 30 s and are rescheduled; check
  `kubectl get nodes` and `kubectl -n shortener get pods -o wide`.

## 3. Confirm
- The 5 m burn rate is back under 1 and the alert resolves (it needs the 5 m window to clear).
- `make smoke` passes.

## 4. Afterwards
Write a blameless postmortem (template: [the chaos day one](../postmortems/2026-10-30-chaos-day.md)):
timeline, impact in budget spent, what went well, what didn't, action items with owners.
