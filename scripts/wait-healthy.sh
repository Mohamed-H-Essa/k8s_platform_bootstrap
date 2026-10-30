#!/usr/bin/env bash
# Wait until every Argo CD Application is Synced and Healthy (the root app plus the
# ones platform/apps renders). Prints progress; on timeout lists what is not ready.
#
#   TIMEOUT=1800 scripts/wait-healthy.sh
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export KUBECONFIG=${KUBECONFIG:-$ROOT/.local/kubeconfig}
TIMEOUT=${TIMEOUT:-1800}
# root + every Application in the app-of-apps chart
EXPECTED=$(( $(helm template "$ROOT/platform/apps" | grep -c '^kind: Application$') + 1 ))

start=$(date +%s)
last=""
while :; do
  rows=$(kubectl -n argocd get applications.argoproj.io --no-headers \
    -o custom-columns='N:.metadata.name,S:.status.sync.status,H:.status.health.status' 2>/dev/null | grep . || true)
  total=$(grep -c . <<<"$rows" || true)
  pending=$(awk 'NF && ($2!="Synced" || $3!="Healthy") {printf "%s(%s/%s) ", $1, $2, $3}' <<<"$rows")
  ready=$(awk 'NF && $2=="Synced" && $3=="Healthy"' <<<"$rows" | grep -c . || true)
  elapsed=$(( $(date +%s) - start ))

  if (( total >= EXPECTED )) && [[ -z $pending ]]; then
    printf '[%3dm%02ds] all %d Applications Synced and Healthy\n' $((elapsed/60)) $((elapsed%60)) "$total"
    exit 0
  fi
  line="$ready/$EXPECTED ready  ${pending:-(waiting for Applications to appear)}"
  if [[ $line != "$last" ]]; then
    printf '[%3dm%02ds] %s\n' $((elapsed/60)) $((elapsed%60)) "$line"
    last=$line
  fi
  if (( elapsed > TIMEOUT )); then
    echo "timed out after ${TIMEOUT}s; not ready: ${pending:-none}" >&2
    kubectl -n argocd get applications.argoproj.io >&2 || true
    exit 1
  fi
  sleep 10
done
