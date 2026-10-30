# CloudNativePG for Postgres

**Status:** accepted

## Context
The shortener stores links in Postgres. The database must survive losing its pod or its node,
fail over without a human, and be declared in Git like everything else.

## Decision
- Run Postgres with the **CloudNativePG** operator: a `Cluster` with two instances (a primary and a
  streaming replica), preferred anti-affinity across nodes, 1 GiB volumes.
- The app connects only to the `shortener-db-rw` Service, which the operator always points at the
  current primary. Credentials come from the operator-generated Secret `shortener-db-app`.
- The app's readiness probe does **not** check the database. If it did, a failover would make every
  pod unready at once and empty the Service; instead requests fail fast with 503 and recover as
  soon as the new primary accepts connections.

## Alternatives
- **A hand-written StatefulSet**: no failover, no backups, no replica management.
- **Zalando postgres-operator / Crunchy PGO**: mature, Patroni-based. CloudNativePG talks to the
  Kubernetes API directly (no separate consensus store) and is a CNCF project.
- **A managed database (RDS)**: the right default on AWS; not available on a laptop. The workload
  only needs a connection string, so swapping is a Secret change.

## Consequences
- Failover is automatic and measured on chaos day (see the postmortem).
- With local-path storage an instance cannot move to another node; the operator recovers by
  promoting the replica and later re-cloning or restarting the lost instance.
- Two instances on two workers is the minimum for HA; a third instance (and synchronous
  replication) would be the production setting to avoid losing acknowledged writes.
