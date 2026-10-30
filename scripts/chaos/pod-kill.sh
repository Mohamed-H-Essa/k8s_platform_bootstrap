#!/usr/bin/env bash
# Experiment 1: kill one shortener pod with no grace period (like a crash or an OOM kill).
# Hypothesis: the other pod keeps serving, the ReplicaSet replaces the dead one, and
# users see at most a handful of failed requests.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

desired=$(desired_pods)
victim=$(kubectl -n $NS get pods -l $SEL -o jsonpath='{.items[0].metadata.name}')
node=$(kubectl -n $NS get pod "$victim" -o jsonpath='{.spec.nodeName}')
log "pod-kill: deleting $victim on $node with --grace-period=0 ($desired pods desired)"
t0=$(now)
kubectl -n $NS delete pod "$victim" --grace-period=0 --force --wait=false >/dev/null 2>&1

recovered() { (( $(ready_pods "$victim") >= desired )); }
took=$(wait_for 300 "$desired ready pods again" -- recovered)
t1=$(now)
log "pod-kill: $desired/$desired ready again after ${took}s"
sleep 10 # let in-flight requests land in the CSV
client=$(k6_window "$t0" "$(now)")
log "pod-kill: client view $client"
record pod-kill "$t0" "$t1" "recovery_s=$took" $client
