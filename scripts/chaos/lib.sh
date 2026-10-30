# Shared helpers for the chaos experiments (sourced, not run).
#
# Every experiment appends one line to $OUT/results.tsv:
#   name  start(epoch)  end(epoch)  key=value measurements...
# and writes a human timeline to $OUT/timeline.log. Prometheus is reached through the
# API server proxy, not the gateway, so a broken gateway can't hide the evidence.

ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
export KUBECONFIG=${KUBECONFIG:-$ROOT/.local/kubeconfig}
export OUT=${OUT:-$ROOT/.local/chaos/manual-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"
NS=shortener
SEL=app.kubernetes.io/name=shortener

now() { date +%s; }
# to stderr (and the file), so $(…) only ever captures results
log() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$OUT/timeline.log" >&2; }
record() { printf '%s\n' "$(IFS=$'\t'; echo "$*")" >>"$OUT/results.tsv"; }

# Prometheus instant query → first value (or NaN)
PROM_PROXY=/api/v1/namespaces/monitoring/services/kps-prometheus:9090/proxy
prom() {
  kubectl get --raw "$PROM_PROXY/api/v1/query?query=$(jq -rn --arg q "$1" '$q|@uri')" 2>/dev/null |
    jq -r '.data.result[0].value[1] // "NaN"'
}
# state of an alert in Prometheus: inactive | pending | firing
alert_state() {
  local s
  s=$(kubectl get --raw "$PROM_PROXY/api/v1/alerts" 2>/dev/null |
    jq -r --arg a "$1" '[.data.alerts[] | select(.labels.alertname==$a) | .state] | if index("firing") then "firing" elif index("pending") then "pending" else "inactive" end')
  echo "${s:-inactive}"
}
# number of alerts with this name that Alertmanager has received
am_count() {
  kubectl get --raw "/api/v1/namespaces/monitoring/services/kps-alertmanager:9093/proxy/api/v2/alerts?filter=alertname%3D$1" 2>/dev/null |
    jq 'length' 2>/dev/null || echo 0
}

# Ready shortener pods (optionally excluding one by name), and the desired count
ready_pods() {
  kubectl -n $NS get pods -l $SEL -o json |
    jq --arg skip "${1:-}" '[.items[] | select(.metadata.name != $skip and .metadata.deletionTimestamp == null)
      | select(any(.status.conditions[]?; .type=="Ready" and .status=="True"))] | length'
}
desired_pods() { kubectl -n $NS get deploy shortener -o jsonpath='{.spec.replicas}'; }

# wait_for SECONDS DESCRIPTION -- COMMAND...: poll every second until COMMAND (a command
# or a function) succeeds.
# Prints the seconds it took; returns 1 on timeout.
wait_for() {
  local limit=$1 what=$2 start; shift 3
  start=$(now)
  until "$@" >/dev/null 2>&1; do
    if (( $(now) - start > limit )); then log "timeout after ${limit}s waiting for: $what"; return 1; fi
    sleep 1
  done
  echo $(( $(now) - start ))
}

# Client-side view from the k6 request log (run-all.sh starts k6 with LOG_REQUESTS=1):
# requests and failed requests between two epochs, and the first and last failure.
k6_window() { # start end → "requests=N failed=N first_fail=HH:MM:SS last_fail=HH:MM:SS"
  local log=$OUT/requests.log n f ff lf
  [[ -f $log ]] || { echo "requests=n/a failed=n/a"; return; }
  read -r n f ff lf < <(awk -v s="$1" -v e="$2" '
    $1 ~ /^[0-9]+$/ { t = int($1 / 1000) }
    $1 ~ /^[0-9]+$/ && t >= s && t <= e { n++; if ($4 == 0) { f++; if (!ff) ff = t; lf = t } }
    END { print n+0, f+0, ff+0, lf+0 }' "$log")
  printf 'requests=%d failed=%d' "$n" "$f"
  (( f )) && printf ' first_fail=%s last_fail=%s' "$(date -r "$ff" +%H:%M:%S)" "$(date -r "$lf" +%H:%M:%S)"
  echo
}
