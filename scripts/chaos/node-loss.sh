#!/usr/bin/env bash
# Experiment 2: lose a worker node (docker stop: like a VM that vanishes) and bring it back.
# Hypothesis: the node goes NotReady within ~a minute, its shortener pod is replaced on
# the other worker 30 s later (tolerationSeconds), and requests fail only while the dead
# endpoints are still in rotation.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

desired=$(desired_pods)
# a worker that runs a shortener pod, preferably not the database primary's node
# (losing the primary is experiment 3)
primary=$(kubectl -n $NS get clusters.postgresql.cnpg.io shortener-db -o jsonpath='{.status.currentPrimary}')
primary_node=$(kubectl -n $NS get pod "$primary" -o jsonpath='{.spec.nodeName}')
nodes=$(kubectl -n $NS get pods -l $SEL -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u)
victim=$(grep -vx "$primary_node" <<<"$nodes" | head -1 || true)
victim=${victim:-$(head -1 <<<"$nodes")}
on_it=$(kubectl get pods -A --field-selector "spec.nodeName=$victim" --no-headers | awk '{print $1"/"$2}' | tr '\n' ' ')
log "node-loss: stopping $victim (DB primary is on $primary_node). Pods there: $on_it"

t0=$(now)
trap 'docker start "$victim" >/dev/null 2>&1 || true' EXIT # never leave the node stopped
docker stop "$victim" >/dev/null

not_ready() { [[ $(kubectl get node "$victim" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}') != True ]]; }
wait_for 300 "$victim NotReady" -- not_ready >/dev/null
t_nr=$(( $(now) - t0 ))
log "node-loss: $victim NotReady at +${t_nr}s"

# ready shortener pods that are NOT on the stopped node
healthy() {
  (( $(kubectl -n $NS get pods -l $SEL -o json | jq --arg n "$victim" '[.items[]
     | select(.spec.nodeName != $n and .metadata.deletionTimestamp == null)
     | select(any(.status.conditions[]?; .type=="Ready" and .status=="True"))] | length') >= desired ))
}
wait_for 600 "$desired ready pods off $victim" -- healthy >/dev/null
t1=$(now)
t_rs=$(( t1 - t0 ))
log "node-loss: $desired/$desired shortener pods ready on the surviving nodes at +${t_rs}s"

sleep 30 # watch the traffic settle before bringing the node back
client=$(k6_window "$t0" "$(now)")
log "node-loss: client view while the node was down: $client"

docker start "$victim" >/dev/null
node_ready() { ! not_ready; }
t_back=$(wait_for 600 "$victim Ready again" -- node_ready)
log "node-loss: $victim Ready again ${t_back}s after docker start"
record node-loss "$t0" "$t1" "node=$victim" "notready_s=$t_nr" "pods_ready_s=$t_rs" "node_back_s=$t_back" $client
