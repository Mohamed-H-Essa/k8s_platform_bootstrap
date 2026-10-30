#!/usr/bin/env bash
# Experiment 3: kill the Postgres primary (no grace period).
# Hypothesis: CloudNativePG promotes the replica within seconds and points
# shortener-db-rw at it; requests fail fast (503) only during the switch; the old
# primary comes back as a replica of the new one.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

cluster() { kubectl -n $NS get clusters.postgresql.cnpg.io shortener-db -o jsonpath="$1"; }
old=$(cluster '{.status.currentPrimary}')
log "db-failover: killing primary $old ($(cluster '{.status.readyInstances}')/$(cluster '{.spec.instances}') instances ready)"
t0=$(now)
kubectl -n $NS delete pod "$old" --grace-period=0 --force --wait=false >/dev/null 2>&1

# a new primary is elected and its pod is Ready
promoted() {
  local p; p=$(cluster '{.status.currentPrimary}')
  [[ -n $p && $p != "$old" ]] &&
    [[ $(kubectl -n $NS get pod "$p" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}') == True ]]
}
wait_for 300 "a new primary" -- promoted >/dev/null
t_fo=$(( $(now) - t0 ))
new=$(cluster '{.status.currentPrimary}')
log "db-failover: $new is the primary at +${t_fo}s"

# the old primary rejoins as a replica: all instances ready again
all_ready() { [[ $(cluster '{.status.readyInstances}') == "$(cluster '{.spec.instances}')" ]]; }
wait_for 600 "all instances ready" -- all_ready >/dev/null
t1=$(now)
t_full=$(( t1 - t0 ))
log "db-failover: all instances ready again at +${t_full}s (phase: $(cluster '{.status.phase}'))"

sleep 10
client=$(k6_window "$t0" "$(now)")
log "db-failover: client view $client"
record db-failover "$t0" "$t1" "old=$old" "new=$new" "failover_s=$t_fo" "replica_back_s=$t_full" $client
