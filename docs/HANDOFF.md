# HANDOFF: Slipway (read this first)

Written 2026-10-30 by the agent that started the rebuild, for whoever continues it.
The owner asked for this repo (`k8s_platform_bootstrap`, public on GitHub, 8 stars, only 2 commits from
March 2026, never actually runnable: its Argo CD app pointed at `your-org`) to be **finished into a
production-style GitOps platform that runs entirely on a laptop** (the owner has **no AWS account**), then:

1. explain the project in detail so the owner can talk about it in interviews,
2. add it to the portfolio site (`~/work/dark_portfolio`) and to the Cloud/DevOps CV,
3. produce a social-media / PR kit for it.

The owner said: implement fully, **don't ask questions**, use best judgement, make it very impressive and very
relevant to platform / DevOps / SRE roles. Owner: Mohamed H. Essa (pronouns not stated: use "the owner" / they).

---

## 1. The idea in one paragraph

**Slipway** (project name; the repo keeps its old name) = `make up` builds a complete platform on a laptop:
a 3-node Kubernetes cluster in Docker (kind), created by **Terraform**, with a private OCI registry, pull-through
image caches and a Git server next to it; **Argo CD** syncs the whole platform from Git (app of apps, sync waves);
**Envoy Gateway** (Gateway API) in front; **Prometheus/Grafana/Loki/Tempo + OpenTelemetry** for metrics, logs and
traces; **CloudNativePG** runs Postgres with a replica and automatic failover; **Kyverno** only admits images that
are **signed (cosign) and carry a signed SBOM (Syft)**, after a **Trivy** scan; the workload is a small **Go URL
shortener** with two **SLOs** and **multi-window burn-rate alerts**. Then a **chaos day** (pod kill, node loss,
database primary kill, a bad release rolled back with `git revert`) is run **under load (k6)**, recovery is
**measured**, and written up as a **postmortem**. An **AWS environment** (EKS, spot nodes, GitHub OIDC, budgets)
is written in Terraform and checked offline (`validate`, `tflint`, `trivy config`) but never applied.

---

## 2. Status (what exists, what works)

| Area | State |
|---|---|
| `app/` Go service | **Done and tested** (`go test -race` passes). Not yet run in the cluster. |
| `app/Dockerfile` | Written (golang:1.27-alpine → distroless static nonroot). **Image build not yet verified** (base image was still downloading). |
| `infra/terraform/envs/local/` | Written (kind + registry + 4 caches + soft-serve + Argo CD + root app). **Never applied; `terraform init` not run yet.** |
| `infra/terraform/envs/local/containerd/certs.d/` | hosts.toml per registry (caches + plain-HTTP local registry). |
| `platform/apps/` (Helm chart, app of apps) | Written. Renders 13 Applications + an OCI repo Secret. Not yet synced. |
| `platform/values/*.yaml` | Written for every chart (sizes trimmed for 8 GB). Unverified against live charts. |
| `platform/gateway/` | Envoy Gateway: EnvoyProxy (NodePort 30080), GatewayClass `envoy`, Gateway `platform`, routes for Grafana / Argo CD / Prometheus. |
| `platform/policies/` | Kyverno: `verify-platform-images` (cosign signature + SPDX attestation, key from Secret `kyverno/cosign-pub`), `restricted-workloads` (version pinned, no :latest, requests+memory limit, non-root, no escalation) for namespaces labelled `slipway.dev/policy=restricted`. |
| `platform/observability/` | SLO recording + alerting rules (`slo-rules.yaml`), Grafana dashboard ConfigMap (`dashboard-shortener.yaml`). |
| `platform/workloads/shortener/` | base (namespace, CNPG Cluster ×2, Deployment, Service, HPA+PDB, ServiceMonitor, HTTPRoute) + overlays `local` (registry `slipway-registry:5000`, tag `0.1.0`) and `aws` (GHCR). `kubectl kustomize` renders OK. |
| `Makefile` | Written. Calls scripts that **don't exist yet** (see §5). |
| `scripts/` | **To write** (old `scripts/setup.sh`, `scripts/destroy.sh` are from the old repo → delete). |
| AWS env, CI, README, docs, chaos day | **To do** (§5). |
| Old repo content | `terraform/` (custom VPC + EKS modules, prod env), `kubernetes/`, old docs (`docs/*_EXPLAINED.md`, `BEGINNERS_GUIDE.md`, `PROJECT_SUMMARY.md`, `DOCUMENTATION_OVERVIEW.md`, `CONTRIBUTING.md`): **replace**. Reuse ideas from `terraform/modules/{vpc,eks}` for the AWS env, then delete the old tree. Keep `LICENSE`. |

Nothing is committed yet except `.gitignore` changes (see §8 for the commit plan). **Do not push to GitHub
until the platform works end to end and CI is green locally (actionlint)**: the repo is public.

---

## 3. Environment gotchas on this Mac (important, all found the hard way)

1. **Always `source ~/work/k8s_platform_bootstrap/.local/env.sh` first.** It sets:
   - `PATH=$HOME/work/k8s_platform_bootstrap/.local/bin:/opt/homebrew/bin:$PATH`
   - `DOCKER_CONFIG=$HOME/work/k8s_platform_bootstrap/.local/docker` (an empty config)
   - `DOCKER_HOST=unix://$HOME/.orbstack/run/docker.sock`

   **Why:** the macOS keychain credential helper `docker-credential-osxkeychain` **hangs forever** on this
   machine (it waits on a keychain prompt nobody answers). The Docker CLI calls it on every `docker pull`, and
   even with an empty config the CLI picks it by default. Result: every pull and every `helm show chart oci://…`
   hangs with no output. `.local/bin/docker-credential-osxkeychain` is a stub that answers "credentials not
   found" at once. The daemon itself pulls fine; it was the CLI. **Never kill the user's real helper config;
   only use the env above.**
2. Docker is **OrbStack** (8 CPU, 8 GB). I set `orb config set network_proxy none` while debugging and then put
   it back to `auto` (it applies at the next OrbStack restart). The proxy was not the problem.
3. Network is slow: about **1.2 MB/s**. Big image pulls take minutes. The local env runs pull-through caches
   (volumes survive `make down`), so each image is downloaded once.
4. macOS has no `timeout`. Use `perl -e 'alarm N; exec @ARGV' cmd` (it does NOT stop the Go docker CLI,
   which ignores SIGALRM) or run in background and `kill` after a loop.
5. `kubectl`: `/usr/local/bin/kubectl` is v1.33; `/opt/homebrew/bin/kubectl` is v1.37 (use this, the env does).
6. Terraform is **1.5.7** (the last MPL version, `/usr/local/bin`): keep syntax compatible (no `removed {}`,
   no S3 native locking; use DynamoDB locks in the AWS backend example).
7. `tflint` is not in Homebrew core any more: run it from Docker
   `docker run --rm -v "$PWD":/data -t ghcr.io/terraform-linters/tflint`.
8. Installed via brew: go 1.27.3, cosign 3.1.4, syft 1.55, k6 2.3, kubeconform 0.8, yq 4.54, actionlint 1.7,
   kyverno CLI 1.19, kubernetes-cli 1.37. Already present: kind 0.31 (k8s 1.35 node image), helm 4.1.4,
   argocd CLI 3.4, trivy, gh, jq.
9. **tmux rules from the owner (CLAUDE.md):** run builds/servers/long commands in the tmux window
   `claude_work` of the session `dark` (`tmux send-keys -t dark:claude_work.<pane>`), never in window 1, never
   create sessions/windows other than `claude_work`, never clear scrollback. Panes right now:
   - pane id `%130` (index 1): general commands (cwd dark_portfolio)
   - pane id `%254` (index 2): **the platform work** (cwd this repo)
   - pane id `%143` (index 3): **the portfolio preview server (`astro preview`) — do not kill**
   Use pane ids (`-t %254`), the indexes shift when panes are split.
10. Base images being pulled at handoff time (pane `%130`): `kindest/node:v1.35.0@sha256:452d70…`,
    `registry:2.8.3`, `golang:1.27-alpine`, `distroless/static-debian12:nonroot` (done), `grafana/k6`.
    Check with `docker images`.

---

## 4. Decisions (and why), so nobody re-litigates them

- **Local first, AWS validated.** No AWS account. Everything must run on kind; the AWS env proves the design
  translates (EKS etc.) and is checked offline. Say so honestly in the README ("not applied: no account").
- **Gateway API with Envoy Gateway, not ingress-nginx**: the community ingress-nginx was retired in 2026.
  Hosts: `*.localtest.me` (public DNS → 127.0.0.1). kind maps host `127.0.0.1:80` → NodePort `30080`.
- **Git server outside the cluster (soft-serve container on the `kind` network)** plays GitHub, so GitOps
  (including "roll back with `git revert`") works offline. Argo CD reads
  `http://slipway-git:23232/platform.git` (anonymous read). `make publish` pushes `HEAD` over SSH
  (`localhost:23231`, key `.local/git_ed25519`, admin via `SOFT_SERVE_INITIAL_ADMIN_KEYS`). On AWS the same tree
  syncs from GitHub (`platform/apps` values `repoURL`, `env: aws`).
- **App of apps is a Helm chart** (`platform/apps`) so `repoURL`, `revision`, `env` are values; each component
  takes `platform/values/<name>.yaml` + `platform/values/<env>/<name>.yaml` (missing files ignored).
  Sync waves: 0 operators/CRDs, 1 things built on them, 2 the workload. Argo CD gets an Application health
  check in `argocd-cm` so waves really wait (see `platform/values/argocd.yaml`).
- **Registry naming:** images are referenced as `slipway-registry:5000/shortener:<tag>` everywhere (that name
  resolves on the kind network). The host pushes to `localhost:5001` (same registry). **Sign with the in-cluster
  name**: run cosign **v2** in a container on the `kind` network (`ghcr.io/sigstore/cosign/cosign:v2.4.1`,
  `--allow-insecure-registry`, `--tlog-upload=false`), so the signature's docker-reference matches what Kyverno
  verifies. (cosign v3 changed the bundle format; stick to v2 for Kyverno compatibility.)
- **Supply chain gate:** Kyverno verifies signature + SPDX attestation (`cosign attest --type spdxjson`) for
  `slipway-registry:5000/*`, mutates the tag to the verified digest. Public key: Secret `kyverno/cosign-pub`
  (key `cosign.pub`), created by `make up` from `.local/cosign.pub`. Kyverno needs
  `features.registryClient.allowInsecure: true` (plain HTTP registry).
- **Postgres via CloudNativePG**, 2 instances (primary + replica, anti-affinity preferred). App uses Secret
  `shortener-db-app` key `uri` (→ `shortener-db-rw`). Readiness does NOT check the DB on purpose (see app code).
- **SLOs:** availability 99.5 % (5xx), latency 95 % < 300 ms (`le="0.3"` bucket). Multi-window burn-rate alerts:
  page = 1 h & 5 m > 14.4×, ticket = 6 h & 30 m > 6×. Expect ~4–15 min to page depending on the error rate
  (that is the honest behaviour of a 1 h window; write it in the postmortem as time-to-detect).
- **Fault injection** is a documented env var on the Deployment (`FAULT_ERROR_RATE`, `FAULT_EXTRA_LATENCY`,
  read at start). The "bad release" chaos experiment changes it **in Git** and rolls back with `git revert`.
- Sizing: everything has small requests/limits (8 GB VM). Dex, notifications, ApplicationSets, Kyverno cleanup
  controller, Loki caches/gateway/canary are off. kube-prometheus-stack: etcd/scheduler/controller-manager/proxy
  scraping off (kind binds them to localhost).
- **Chart versions** (as of 2026-10-30): argo-cd 10.11.6 (app v3.5.6), argocd-apps 2.0.7,
  kube-prometheus-stack 92.16.1, loki 7.5.0, tempo 1.24.4, alloy 1.15.0, opentelemetry-collector 0.178.1,
  cloudnative-pg 0.29.1, kyverno 3.9.2, metrics-server 3.14.0, envoy gateway-helm 1.9.3 (OCI
  docker.io/envoyproxy). soft-serve image `charmcli/soft-serve:v0.12.4`. Default values for every chart are
  saved in `.local/chart-values/<chart>.yaml` (gitignored) for reference.
- Fixed names (via `fullnameOverride`): `kps-prometheus`, `kps-grafana`, `kps-alertmanager`;
  `otel-collector.monitoring:4318`; `loki.monitoring:3100`; `tempo.monitoring:3200/4317`.

### Things I could not verify yet (check them first when the cluster is up)
1. The containerd patch in `envs/local/main.tf` uses the containerd **2.x** key
   `plugins."io.containerd.cri.v1.images".registry.config_path`. Check
   `docker exec slipway-control-plane cat /etc/containerd/config.toml`; kind may already set `config_path`.
   If containerd fails to start, drop the patch.
2. Whether **pods** (Kyverno) resolve `slipway-registry` by name. If not: a CoreDNS `hosts`/`rewrite` entry or a
   Service + EndpointSlice pointing at the container IP.
3. soft-serve: repo auto-created on first admin push; anonymous HTTP read enabled by default.
4. Argo CD + OCI Helm repo for Envoy Gateway (`docker.io/envoyproxy`, `enableOCI`): may need `oci://` form in
   Argo CD 3.5; adjust the Secret/repoURL if the app errors.
5. EnvoyProxy NodePort patch (strategic merge on `ports` by `port`).
6. Alloy config syntax (`sys.env`, `coalesce`), Loki 7.x values names, `crds.enabled` in kps.
7. Kyverno + cosign v2 signatures/attestations from a plain-HTTP registry.
8. Memory headroom in 8 GB: if pods get OOM-killed or Pending, trim (e.g. Alertmanager, Kyverno reports
   controller) and note it.

---

## 5. What is left, in order (with acceptance criteria)

### A. Make it run (critical path)
1. **Scripts** referenced by the Makefile (bash, `set -euo pipefail`, short comments):
   - `scripts/release-image.sh TAG`: `docker build` (`app/`, `--build-arg VERSION=TAG`) as
     `localhost:5001/shortener:TAG` → `trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed` →
     `docker push` → digest → `syft` SBOM (spdx-json, to `.local/sbom-TAG.spdx.json`) → cosign v2 container on
     network `kind`: `sign` and `attest --type spdxjson` against `slipway-registry:5000/shortener@<digest>`
     (key `.local/cosign.key`, `COSIGN_PASSWORD=` empty) → print digest.
   - `scripts/wait-healthy.sh`: poll `kubectl -n argocd get applications` until all Synced+Healthy (timeout
     ~30 min), print a compact table as it goes, exit non-zero with the unhealthy ones on timeout.
   - `scripts/smoke.sh`: `POST http://sho.localtest.me/api/links` → follow the short link → expect 302 to the
     URL; also check Grafana and Argo CD answer 200/302 through the gateway.
   - `scripts/try-unsigned.sh`: push an unsigned image (e.g. busybox retagged to the local registry) and try to
     run it in `shortener`; expect Kyverno to refuse; print the refusal.
   - `scripts/load.js` (k6): ~2 min, mix of creates and redirects against sho.localtest.me, thresholds
     (p95 < 300 ms, errors < 0.5 %), summary to stdout.
   - `scripts/lint-manifests.sh`: `helm template platform/apps`, `kubectl kustomize` each dir, `kubeconform`
     (with CRD schemas from datreeio catalog, `-ignore-missing-schemas`), `kyverno` CLI tests if any.
   - `scripts/chaos/*.sh` + `run-all.sh` (see C).
2. `make up` from nothing until **every Application is Synced+Healthy**, `make smoke` passes, `make unsigned` is
   refused, Grafana dashboard "Shortener · service and SLOs" shows traffic, a trace opens in Tempo from an
   exemplar, error logs appear in Loki. Fix whatever breaks (see §4 "could not verify").
3. `make release` works end to end (new tag → signed → committed → Argo CD rolls out, zero failed requests
   under `make load`).
4. Record **real numbers** (no invented metrics, ever): `make up` time cold vs warm cache, image size, k6 p95 /
   RPS / error rate on the laptop, time for Argo CD to roll a release.

### B. Chaos day (run under `make load`, measure with Prometheus queries and k6 output)
1. Kill one shortener pod → errors seen? time until 2/2 ready.
2. Stop a worker node (`docker stop slipway-worker`) → time until pods rescheduled (tolerationSeconds 30) and
   traffic healthy; start it again.
3. Kill the Postgres primary pod → CNPG failover time; write errors during failover.
4. Bad release via Git (`FAULT_ERROR_RATE: "0.5"` commit + publish) → time until the burn-rate page fires
   (Alertmanager / Prometheus alerts API), `git revert` + publish → time to recover.
Write `docs/chaos-day.md` (how to run) and `docs/postmortems/2026-10-30-chaos-day.md` (blameless format:
summary, impact, timeline with real timestamps, what went well, what didn't, action items).

### C. AWS environment (offline-validated)
`infra/terraform/envs/aws` + `infra/terraform/modules/{vpc,eks,...}` (reuse/clean the old custom modules or use
terraform-aws-modules; justify in an ADR): VPC (3 AZ, private nodes, 1 NAT for cost), EKS 1.35 with a **spot**
managed node group (+ small on-demand system group), **scheduled scale-down** at night
(`aws_autoscaling_schedule`), IRSA/Pod Identity for EBS CSI, **GitHub OIDC provider + role** for CI (no static
keys), **AWS Budgets** alarm, S3 backend example with DynamoDB lock, Argo CD bootstrap (same chart, `env: aws`,
`repoURL` = GitHub). `make aws-check` = `terraform init -backend=false && validate`, tflint (docker), `trivy
config`. All clean. No apply.

### D. CI (`.github/workflows/`), must pass `actionlint`
- `ci.yml`: Go vet/test, build image, Trivy scan, Syft SBOM, on `main` push to GHCR and **keyless** cosign sign
  + attest (GitHub OIDC), Terraform fmt/validate (both envs), manifest lint.
- `e2e.yml` (manual + weekly): kind in CI, `make up` (maybe a smaller profile), `make smoke`, `make unsigned`.
- Keep permissions minimal (`contents: read`, `packages: write`, `id-token: write` only where needed), pin
  actions to versions.

### E. Docs and README (concise, accurate, no fluff)
- `README.md`: what it is, the architecture diagram (Mermaid), `make up` quick start + requirements (Docker 8 GB),
  what you get (URLs), the numbers from A4/B, how GitOps/release/supply chain/SLOs work, what's local vs AWS,
  repo map. Badges (CI).
- `docs/architecture.md`, `docs/slo.md`, `docs/runbooks/slo-burn.md` (the alert's runbook_url points there),
  `docs/runbooks/database-failover.md`, `docs/adr/` (short ADRs: kind+Terraform, Gateway API, soft-serve,
  CNPG, Kyverno+cosign, burn-rate SLOs), `docs/chaos-day.md`, postmortem.
- **`docs/interview-guide.md`**: the owner's script to explain the project: 60-second pitch, a 5-minute
  walkthrough, each component and "why this and not X", likely interview questions with honest answers
  (e.g. "why not ingress-nginx", "how does the burn-rate alert work", "what happens when the primary dies",
  "how would this run on AWS", "what would you change for production"), the real numbers.
- Delete the old docs and trees (§2).

### F. Ship it
Commit in logical commits (app, infra, platform, scripts, docs, CI). Secrets check before pushing
(`gitleaks` via Docker, or grep for keys; `.local/` is ignored). Push to `origin main` (public repo
`Mohamed-H-Essa/k8s_platform_bootstrap`), watch CI with `gh run watch`, fix until green. Optionally rename the
GitHub repo description/topics.

### G. Portfolio follow-up (repo `~/work/dark_portfolio`, read its `docs/HANDOFF.md` first)
- New project node (e.g. slug `slipway`, code `C04`, worlds `[cloud, origin]`, start 2026-03 (first commit) →
  present, links.github), facts only from this repo and the measured numbers; DE/AR drafts with
  `review: {de: true, ar: true}`; `assets-src/slipway/diagram.yaml` (cover-cloud template) + `npm run assets --
  slipway`; a page visual (new `visual` key, e.g. a GitOps/release flow or the chaos-day timeline; see
  `src/components/demo/*` for the pattern and `src/content.config.ts` for the enum).
- CV: the site serves `public/cv/Mohamed-Essa-Cloud-DevOps.pdf` and `Mohamed-Essa-Mobile-Engineer.pdf`. Find the
  CV source (search `~/work` and `~/Downloads` for the DevOps resume source: `.tex`, `.html`, `.docx`, or a
  generator; `~/work/latex_cv/cv_latex.tex` is an older LaTeX CV). Add the project to the DevOps CV (and one line
  to the mobile CV if it fits), regenerate the PDF, replace the file **keeping the filename**.
- PR kit `docs/pr/slipway.md` in dark_portfolio: LinkedIn launch post, a technical deep-dive post, a chaos-day
  post, a carousel outline (and ideally rendered slides), an X/Twitter thread, a dev.to/Medium article outline,
  what to record (terminal + Grafana during chaos), posting schedule. All claims factual.
- `npm run check && npm run build`, look at the page at 1440/390 in en+ar, commit, push to `main` (deploys).

---

## 6. File map (new structure)

```
Makefile                         entry point (make help)
app/                             Go service: cmd/shortener, internal/shortener (+ tests), Dockerfile
infra/terraform/envs/local/      kind + registry + caches + git + Argo CD (+ containerd/certs.d)
infra/terraform/envs/aws/        (to do) EKS etc., validated offline
platform/apps/                   Helm chart: the app of apps
platform/values/                 values per component (+ <env>/ overrides)
platform/gateway/                Envoy Gateway + platform routes
platform/policies/               Kyverno policies
platform/observability/          SLO rules + Grafana dashboard
platform/workloads/shortener/    base + overlays/{local,aws}
scripts/                         (to do) release, wait, smoke, unsigned, load, lint, chaos
docs/                            this handoff + (to do) architecture, slo, runbooks, adr, chaos day, postmortem, interview guide
.local/                          gitignored: env.sh, bin/ (credential stub), docker/ config, keys, kubeconfig, chart values
```

## 7. Service facts (for docs and the interview guide)
- API: `POST /api/links {"url"}` → 201 `{code, url, short_url}`; `GET /{code}` → 302 (counts the hit in the
  same UPDATE); `GET /api/links/{code}` → stats. Admin port 9090: `/livez`, `/readyz`, `/metrics` (OpenMetrics).
- Codes: 7 chars base62 from crypto/rand (62^7 ≈ 3.5e12), retry on collision (unique violation 23505).
- Metrics: `shortener_http_requests_total{route,method,code}`, `shortener_http_request_duration_seconds`
  (buckets incl. 0.3, exemplars with `trace_id`), `shortener_links_created_total`. Route label is fixed (no
  cardinality explosion from random paths).
- Traces: OTLP/HTTP to the collector, parent-based 20 % sampling. Logs: JSON (slog) with `trace_id` on errors.
- Graceful shutdown: unready → drain 5 s → `Shutdown(20 s)` → flush spans. Timeouts on the server.
- Startup waits for Postgres with backoff (up to ~1 min); schema created idempotently.
- Image: distroless static, non-root 65532, read-only root FS in the pod, all capabilities dropped.

## 8. Commit plan / git state
Working tree has untracked `Makefile app/ infra/ platform/` and a modified `.gitignore`. Commit as you finish
each area; the first commit can be "WIP: Slipway rebuild (app, local infra, GitOps tree)".

---

## 9. Progress log (second agent, 2026-10-30; scope 5A, 5B, 5E, 5F)

- 09:30 base images present. Scripts written: `release-image.sh`, `wait-healthy.sh`, `smoke.sh`,
  `try-unsigned.sh`, `load.js`, `chaos/{lib,pod-kill,node-loss,db-failover,bad-release,run-all}.sh`.
- Fixes found by running `make up` (all committed):
  - kind v0.31's node image writes a **version 2** containerd config → registry key is
    `plugins."io.containerd.grpc.v1.cri".registry` (verified: `config_path` is set in the nodes).
  - OrbStack adds `log_opts` to containers → `lifecycle { ignore_changes = [log_opts] }`; `terraform
    plan` is now a no-op after apply.
  - macOS **web filter proxy (`webfilterproxyd`, 127.0.0.1:10011) resets some HTTPS downloads**
    (GitHub release assets) → `make up` retries `terraform apply` 3×.
  - Trivy blocked the first image: CVE-2026-78669 (HIGH) in `golang.org/x/net` v0.59.0 → v0.60.0.
  - cosign v2 needs `--allow-http-registry` (not `--allow-insecure-registry`) for plain HTTP.
  - Alloy values: `configMap` must be under `alloy:`. Loki rules sidecar off.
  - Argo CD: server-side diff on, repo-server timeouts 300 s + `ARGOCD_EXEC_TIMEOUT=5m`.
  - Grafana chart made a random admin password per render (endless OutOfSync) → Secret
    `monitoring/grafana-admin` created by `make up` from `.local/grafana-password`.
  - Envoy: 2 replicas + PDB + 30 s tolerations; Prometheus/Alertmanager pinned to the control-plane
    node in `platform/values/local/` (so a worker stop on chaos day keeps the evidence).
- Docs written: ADRs (7) in `docs/adr/`, `architecture.md`, `slo.md`, runbooks, `chaos-day.md`,
  README draft (`NUMBERS` placeholder), interview guide draft (`{{…}}` placeholders = measured
  numbers still to fill in).
- Image: 34.2 MB (docker image ls), SBOM 43 packages.
