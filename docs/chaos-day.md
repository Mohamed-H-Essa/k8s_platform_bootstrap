# Chaos day

A normal release and four failures, injected on purpose while k6 sends steady traffic through the
gateway, each with a hypothesis written down first and recovery measured by the scripts, not by
eye. The results
and what we learned are in the [postmortem](postmortems/2026-10-30-chaos-day.md).

## Run it
```bash
make up && make smoke     # a healthy platform first
make chaos                # all five, ~45 minutes, k6 at 50 req/s the whole time
# or one at a time (k6 is started for you):
scripts/chaos/run-all.sh pod-kill
scripts/chaos/run-all.sh db-failover
```
Settings: `RATE` (k6 requests per second, default 50), `SETTLE` (seconds of normal traffic before,
between and after experiments, default 120).

Evidence lands in `.local/chaos/<timestamp>/`:

| File | What |
|---|---|
| `timeline.log` | every action and observation, with wall-clock times |
| `results.tsv` | one line per experiment: start, end, measured durations, client view |
| `requests.log` | one line per k6 request: `epoch_ms status route ok duration_ms` |
| `k6-summary.json`, `k6.log` | k6's end-of-test summary |

While it runs, watch Grafana → **Shortener · service and SLOs** and
`kubectl get pods -A -o wide -w`.

## The experiments

| # | Script | Injects | Hypothesis | Measured |
|---|---|---|---|---|
| 0 | `release.sh` | `make release` (build, scan, SBOM, sign, commit, publish) | a new version rolls out with no failed requests | pipeline time, rollout time, failed requests |
| 1 | `pod-kill.sh` | delete one shortener pod with `--grace-period=0` (a crash) | the other pod serves; the ReplicaSet replaces it; a handful of failed requests at most | seconds until all pods are Ready again; failed requests |
| 2 | `node-loss.sh` | `docker stop` a worker (not the DB primary's), then start it | node NotReady within about a minute; its pods move 30 s later; failures only while dead endpoints are still in rotation | time to NotReady, time until pods are Ready elsewhere, failed requests, time for the node to come back |
| 3 | `db-failover.sh` | delete the Postgres primary pod with `--grace-period=0` | CloudNativePG promotes the replica within seconds; requests fail fast during the switch; the old primary rejoins as a replica | time to a new primary, time until both instances are ready, failed requests |
| 4 | `bad-release.sh` | commit `FAULT_ERROR_RATE=0.5` to the local overlay and publish (half of the redirects answer 500) | the fast-burn page fires; `git revert` + publish recovers | time to roll out, to pending, to firing, to reach Alertmanager; time from revert to clean traffic and to the alert resolving |

### The fault hook
`FAULT_ERROR_RATE` and `FAULT_EXTRA_LATENCY` are environment variables the shortener reads at
start (zero by default, logged loudly when set). They exist so a "bad release" can be shipped the
honest way, through Git, and rolled back the honest way, with `git revert`. `bad-release.sh`
commits the change and the revert itself, so the Git history shows both.

## Safety
- Everything runs against the local kind cluster only.
- `node-loss.sh` restarts the node on exit, even if it fails half way.
- `bad-release.sh` refuses to start if the overlay has uncommitted changes.
- If something is left broken: `git revert` the bad commit and `make publish`, `docker start
  slipway-worker slipway-worker2`, or rebuild with `make down && make up`.
