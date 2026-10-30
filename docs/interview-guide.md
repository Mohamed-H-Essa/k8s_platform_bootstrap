# Interview guide: how to talk about Slipway

A script for explaining this project out loud. Every number here was measured on the owner's
laptop (OrbStack, 8 CPU, 8 GB) and is reproducible with the commands next to it. If someone asks
about something that isn't here, say so; don't round up.

## The 60-second pitch

> "Slipway is a production-style Kubernetes platform that I can bring up on a laptop with one
> command. Terraform creates a three-node kind cluster, a private registry, image caches and a Git
> server, and installs Argo CD; Argo CD then builds the rest of the platform from Git in sync waves:
> Envoy Gateway on the Gateway API, Kyverno, Prometheus, Grafana, Loki, Tempo with OpenTelemetry,
> and CloudNativePG. The workload is a small Go URL shortener with two SLOs and multi-window
> burn-rate alerts.
>
> Releases go through a pipeline that scans with Trivy, generates an SBOM with Syft and signs with
> cosign, and Kyverno refuses any image that isn't signed and attested. Then I ran a chaos day
> under load: killed pods, stopped a node and killed the database primary, measured what users
> saw and how long recovery took, fixed what broke, and wrote a blameless postmortem. (The
> bad-release experiment is scripted but hasn't run yet; say so if asked.) The AWS version
> is written in Terraform and validated offline; I haven't applied it because I don't have an
> account, and I say that in the README."

## The 5-minute walkthrough (with the screen)

1. **README diagram** (30 s): two halves. Outside the cluster: Terraform, registry, caches, Git
   server. Inside: Argo CD, then the platform layers, then the workload.
2. **`make up`** (1 min): show `infra/terraform/envs/local/main.tf`. Terraform stops at Argo CD and
   one root Application; everything else is in `platform/apps` (one line per component, sync
   waves 0 → 2). Mention the pull-through caches: 11 min 20 s from `make down` to all 14 Applications healthy with warm caches; a cold start first pulls 1.77 GB of images through them.
3. **A release** (1 min): `make release`: build, Trivy gate, push, Syft SBOM, cosign sign + attest,
   commit the tag, publish. Argo CD rolls it out with `maxUnavailable: 0`; under 50 req/s of load it took 43–45 s to build and sign and 35–48 s to roll out, with 0 failed requests (two runs).
   Then `make unsigned`: Kyverno's refusal message on screen.
4. **Grafana** (1 min): the SLO dashboard: availability, latency, burn rate with the 14.4× line.
   Click an exemplar on the latency graph → the trace in Tempo → its logs in Loki.
5. **Chaos day** (1.5 min): the postmortem's table: what was injected, time to detect, time to
   recover, what surprised us, what we changed.

## Each component: what it does, why this and not the alternative

| Component | Role | Why this | Instead of |
|---|---|---|---|
| kind + Terraform | 3-node cluster, registry, caches, Git, Argo CD | upstream Kubernetes in Docker; IaC in the same tool as the AWS env | minikube (single node by default), k3d (different distribution), a shell script (no state, no destroy) |
| Argo CD, app of apps as a Helm chart | everything in the cluster comes from Git | sync waves + health checks give ordering; values switch local/AWS | ApplicationSets (better for many clusters), Terraform helm for all (drift found only at next apply) |
| soft-serve | the Git server Argo CD pulls from locally | offline, tiny, `git revert` works like on GitHub, experiments stay private | Gitea (heavy), mounting the repo (not GitOps) |
| Envoy Gateway (Gateway API) | entry point (an Envoy per node locally, 2 replicas + NLB on AWS) | ingress-nginx was retired in March 2026; Gateway API splits platform/team ownership | Traefik, Cilium (replaces the CNI), Istio (a mesh) |
| Kyverno + cosign + Syft + Trivy | only scanned, signed images with an SBOM run | YAML policies, image verification built in, pins the digest | Gatekeeper (Rego + external data), ValidatingAdmissionPolicy (can't verify signatures) |
| kube-prometheus-stack | metrics, alerts, dashboards | the standard; ServiceMonitor/PrometheusRule live with each app | a hosted vendor |
| OpenTelemetry Collector + Tempo | traces | apps only know the collector; backend swappable | Jaeger (fine, separate UI) |
| Alloy + Loki | logs | Promtail is deprecated; Loki indexes labels only, cheap | ELK (JVM, heavy) |
| CloudNativePG | Postgres with a replica and failover | operator talks to the Kubernetes API, no extra consensus store | a StatefulSet (no failover), RDS on AWS |
| SLOs with burn-rate alerts | page on user impact, not on causes | precise and fast to reset (two windows) | static thresholds (noisy or slow) |

## Questions you will likely get, with honest answers

**Why not ingress-nginx?** The community controller was retired (announced November 2025,
maintenance ended March 2026). The Gateway API is GA, more expressive (header matching, traffic
splitting, cross-namespace references with explicit grants) and separates the platform's Gateway
from each team's routes. Envoy Gateway is a standalone implementation, no mesh required.

**How does the burn-rate alert work?** The error budget for 99.5 % is 0.5 %. Burn rate is the
current error ratio divided by the budget; 1× would spend the budget in exactly 30 days. The page
fires when both the 1-hour and the 5-minute burn rates are above 14.4× (2 % of the monthly budget
in one hour). The long window proves it's real; the short one proves it's still happening, so the
alert clears minutes after the fix. For a 50 % error rate on redirects (about 42 % of all
traffic) after a clean hour, that is roughly `60 × 0.072 / 0.42 ≈ 10` minutes plus the 1-minute
`for`. I have not measured it yet: the bad-release experiment is written but did not run on my
laptop (honest answer if asked).

**What happens when the database primary dies?** CloudNativePG notices, promotes the streaming
replica and points the `-rw` Service at it. The app's readiness doesn't depend on the database on
purpose: otherwise every pod goes unready at once and the gateway has nowhere to send traffic.
On chaos day the first attempt failed in an instructive way: the operator itself had just been
moved by the node-loss experiment and was restarting, so nothing promoted the replica for over
5 minutes, and the app hung on the database instead of answering 503. Fixes: two operator
replicas and a 2-second bound on every database call. Lesson: the failover is only as available
as the thing that performs it.

**What happens when a node dies?** Kubernetes marks it NotReady after the node-monitor grace
period; pods tolerate that for 30 s (default is 5 minutes) and then move. Measured: before the fixes, 48 % of requests failed for 6 minutes, because the gateway's
controller and Kyverno's only admission controller were on the lost node (stale endpoints; the
eviction DELETE refused by a fail-closed webhook). After the fixes (two replicas, 30 s
tolerations, Envoy retries and outlier detection, Kyverno never sees DELETE): 2 of 5,719
requests failed and the pods were running elsewhere 84 s after the stop.

**How would this run on AWS?** `infra/terraform/envs/aws`: VPC over three AZs with private nodes
and one NAT (cost), EKS with spot workers and a small on-demand system group, scheduled scale-down
at night, Pod Identity/IRSA for the EBS CSI driver, a GitHub OIDC role for CI (no static keys),
AWS Budgets alarms, S3 state with DynamoDB locking. Argo CD gets the same app-of-apps chart with
`env: aws` and `repoURL` pointing at GitHub. It is validated offline (`terraform validate`,
`tflint`, `trivy config`) but never applied: I don't have an account, and I don't claim otherwise.

**How do you know what's running is what you built?** Kyverno verifies the cosign signature and
the SBOM attestation against the release key and rewrites the tag to the verified digest, so the
pod spec pins the exact bytes that were signed. `make unsigned` shows the refusal.

**Why sign with a key locally but keyless in CI?** Keyless (Fulcio + Rekor) needs an OIDC identity
and the public transparency log; a laptop registry that never leaves the machine doesn't need
either. In GitHub Actions the workflow's OIDC token signs, and nothing long-lived has to be stored.

**What did chaos day find?** Three real problems, all in the platform, not the app: single
replicas with the default 5-minute eviction delay (Envoy Gateway, Kyverno, the CloudNativePG
operator), a fail-closed webhook that also intercepted DELETEs, and an SLI that cannot see
gateway errors. Plus a GitOps trap: Argo CD's server-side diff ignores mutating-webhook changes by
default, and Kyverno rewrites images to `tag@digest`, so a release looked "Synced" and never
rolled out. Each one has a commit that fixes it and a line in the postmortem.

**What broke while building it?** True stories: Trivy blocked the very first image (a HIGH CVE in
`golang.org/x/net`, fixed by bumping it); kind's node image still uses a version-2 containerd
config, so the registry mirror key had to be the old one; the Grafana chart generated a new random
admin password on every render, so Argo CD showed it as permanently out of sync and restarted
Grafana (fixed by creating the Secret outside Git); a local web filter reset some HTTPS downloads,
so `make up` retries Terraform.

**What would you change for production?**
- Three Postgres instances with synchronous replication (no lost writes on failover), backups to
  object storage with point-in-time recovery, and a tested restore.
- Measure the SLI at the gateway as well as the app (the chaos day showed failures the app never sees).
- Gateway retries and outlier detection for idempotent routes; rate limits.
- TLS everywhere (cert-manager), SSO for Argo CD and Grafana, Argo CD projects per team, network
  policies.
- Multiple clusters with ApplicationSets; Renovate for chart and image versions.
- Remote storage for Prometheus/Loki/Tempo; alert routing to a real pager.

**What's the weakest part?** It's one laptop: no real load balancer, local volumes that can't move
between nodes, and numbers that come from a single machine sharing CPU with the load generator.
The design is meant to transfer; the numbers are not a benchmark.

## The numbers

All measured, with method, in the README table and the postmortem. The ones to remember:
cold `make up` on a fresh GitHub runner 10 min 22 s (the e2e workflow), warm on the laptop 11–14 min; image 34.2 MB (7.2 MiB compressed); 2 min at 50 req/s: 6,031
requests, 0 failed, p95 168.5 ms; release under load: 0 failed requests, ~45 s to build and
sign, 35–48 s to roll out; pod kill: 0 failed, 12 s to ready; node loss: 48 % failing for 6 min
before the fixes, 2 failed out of 5,719 after.
