#!/usr/bin/env bash
# Not a failure: an ordinary release under load, as the baseline the failures compare to.
# Runs `make release` (build, scan, SBOM, sign, commit, publish) and measures how long the
# pipeline and the rollout take, and whether any request failed while pods were replaced.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

OVERLAY=platform/workloads/shortener/overlays/local/kustomization.yaml
git diff --quiet HEAD -- "$OVERLAY" || { echo "$OVERLAY has uncommitted changes" >&2; exit 1; }
old=$(yq '.images[0].newTag' "$OVERLAY")
log "release: shipping a new version (current tag $old)"
t0=$(now)
make --no-print-directory release >"$OUT/release.log" 2>&1
new=$(yq '.images[0].newTag' "$OVERLAY")
t_pub=$(now)
log "release: $new built, scanned, signed, committed and published in $(( t_pub - t0 ))s"

image_tag() { kubectl -n $NS get deploy shortener -o jsonpath='{.spec.template.spec.containers[0].image}'; }
rolled() { [[ $(image_tag) == *":$new"* ]] && kubectl -n $NS rollout status deploy/shortener --timeout=1s >/dev/null 2>&1; }
wait_for 600 "the rollout of $new" -- rolled >/dev/null
t1=$(now)
log "release: $new rolled out $(( t1 - t_pub ))s after publish (Argo CD sync + rolling update)"
sleep 10
client=$(k6_window "$t_pub" "$(now)")
log "release: client view during the rollout: $client"
record release "$t0" "$t1" "tag=$new" "pipeline_s=$(( t_pub - t0 ))" "rollout_s=$(( t1 - t_pub ))" $client
