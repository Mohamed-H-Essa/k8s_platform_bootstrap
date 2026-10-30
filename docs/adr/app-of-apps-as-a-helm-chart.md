# The app of apps as a Helm chart, in sync waves

**Status:** accepted

## Context
Terraform installs Argo CD and one root Application; everything else has to come from Git, in
the right order (CRDs and operators before the things that use them), and the same tree has to
serve the local and the AWS environment.

## Decision
- `platform/apps` is a small Helm chart that renders one Argo CD Application per component.
  `repoURL`, `revision` and `env` are values, so the root Application for each environment only
  sets those.
- Upstream charts are pinned to exact versions. Their values come from this repo through a
  multi-source Application: `platform/values/<name>.yaml`, then
  `platform/values/<env>/<name>.yaml` if it exists.
- Sync waves: **0** operators and CRDs (metrics-server, Envoy Gateway, CloudNativePG, Kyverno,
  kube-prometheus-stack), **1** what builds on them (Loki, Tempo, Alloy, the OpenTelemetry
  Collector, gateway routes, policies, SLO rules and dashboards), **2** the workload.
- Argo CD gets a health check for the `Application` kind so a wave really waits until the one
  before it is Healthy.
- Every Application syncs automatically with prune and self-heal, server-side apply (some CRDs
  are too large for client-side apply) and retries with backoff.

## Alternatives
- **ApplicationSets**: better for many clusters or many similar apps; here each component is
  different, and a chart keeps the list readable in one file.
- **Plain Application YAML files**: no place to switch `repoURL` and `env` without duplication.
- **Terraform's helm provider for everything**: a second source of truth, and drift is only
  noticed at the next `terraform apply`.

## Consequences
- Adding a component is one line in `platform/apps/templates/applications.yaml` plus a values file.
- A chart upgrade is a one-line version change, reviewed and rolled back like any commit.
