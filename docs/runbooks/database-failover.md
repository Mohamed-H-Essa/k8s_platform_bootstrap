# Runbook: Postgres primary lost (CloudNativePG failover)

The shortener's database is a CloudNativePG `Cluster` named `shortener-db` in namespace
`shortener`: one primary and one streaming replica on different nodes. The app only talks to the
`shortener-db-rw` Service, which the operator points at the current primary. Background:
[ADR](../adr/cloudnativepg-for-postgres.md).

## What happens on its own
1. The primary's pod or node dies.
2. The operator notices, promotes the replica and moves `shortener-db-rw` to it.
3. Writes and reads fail with 503 for those seconds (the app's readiness does not depend on the
   database, so its pods stay in the Service and recover as soon as the new primary answers).
4. The old primary, once its pod is back, rejoins as a replica of the new one.

Measured on chaos day: see the [postmortem](../postmortems/2026-10-30-chaos-day.md).

## Check
```bash
kubectl -n shortener get clusters.postgresql.cnpg.io shortener-db
#   INSTANCES  READY  STATUS                     PRIMARY
#   2          2      Cluster in healthy state   shortener-db-2
kubectl -n shortener get pods -l cnpg.io/cluster=shortener-db -L role -o wide
kubectl -n shortener get events --sort-by=.lastTimestamp | tail -20
```
With the `kubectl cnpg` plugin: `kubectl cnpg status shortener-db -n shortener`.

## When it does not heal
- **Stuck in "Failing over" or no primary:** look at the operator's log:
  `kubectl -n cnpg-system logs deploy/cnpg-cloudnative-pg | tail -50`.
- **Old primary does not rejoin** (diverged timeline): delete its pod and PVC; the operator
  re-clones it from the new primary.
  ```bash
  kubectl -n shortener delete pvc <old-instance> && kubectl -n shortener delete pod <old-instance>
  ```
- **A whole node is gone for good:** the instance on it cannot move (local volumes). Delete that
  instance's PVC and pod as above; the operator creates a new instance on a healthy node.
- **Manual switchover** (planned maintenance): `kubectl cnpg promote shortener-db <replica> -n shortener`.

## Afterwards
Confirm `make smoke` passes and the availability burn rate is back under 1. If writes were lost
(asynchronous replication can lose the last transactions of a dead primary), note it in the
postmortem; the production fix is a third instance with synchronous replication.
