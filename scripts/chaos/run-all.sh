#!/usr/bin/env bash
# Chaos day: run the four experiments one after another under steady load (k6), and keep
# the evidence in .local/chaos/<timestamp>/ (timeline.log, results.tsv, requests.log,
# k6-summary.json). See docs/chaos-day.md.
#
#   scripts/chaos/run-all.sh                        a release, then the four failures
#   scripts/chaos/run-all.sh pod-kill db-failover   only these
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export OUT=${OUT:-$ROOT/.local/chaos/$(date +%Y%m%d-%H%M%S)}
source "$ROOT/scripts/chaos/lib.sh"

EXPERIMENTS=("$@")
(( ${#EXPERIMENTS[@]} )) || EXPERIMENTS=(release pod-kill node-loss db-failover bad-release)
RATE=${RATE:-50}
SETTLE=${SETTLE:-120} # seconds of normal traffic before, between and after experiments

log "chaos day: ${EXPERIMENTS[*]} at $RATE req/s; evidence in ${OUT#"$ROOT"/}"
LOG_REQUESTS=1 RATE=$RATE DURATION=${DURATION:-3h} \
  k6 run --quiet --console-output "$OUT/requests.log" --log-format raw \
  --summary-export "$OUT/k6-summary.json" "$ROOT/scripts/load.js" >"$OUT/k6.log" 2>&1 &
K6=$!
trap 'kill -INT $K6 2>/dev/null || true' EXIT

sleep "$SETTLE"
log "baseline: $(k6_window $(( $(now) - SETTLE + 10 )) "$(now)")"
for e in "${EXPERIMENTS[@]}"; do
  "$ROOT/scripts/chaos/$e.sh"
  sleep "$SETTLE"
done

kill -INT $K6 && wait $K6 || true
trap - EXIT
log "chaos day done. Results:"
column -t -s $'\t' "$OUT/results.tsv" | tee -a "$OUT/timeline.log"
jq -r '.metrics | "k6 overall: \(.http_reqs.count) requests, \(.http_req_failed.passes // 0) failed, p95 \(.http_req_duration["p(95)"] | floor) ms, p99 \(.http_req_duration["p(99)"] | floor) ms"' \
  "$OUT/k6-summary.json" | tee -a "$OUT/timeline.log" || true
