#!/usr/bin/env bash
# Experiment 4: ship a bad release through Git, let the SLO alert catch it, roll it back
# with `git revert`.
#
# The "bug" is the documented fault hook: FAULT_ERROR_RATE=0.5 makes half of the
# redirects answer 500. It is committed to the local overlay and published, exactly like
# a real release. Measured: time to roll out, time until the fast-burn page fires, time
# from `git revert` to clean traffic, time until the alert resolves.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$ROOT"

OVERLAY=platform/workloads/shortener/overlays/local/kustomization.yaml
ALERT=ShortenerErrorBudgetFastBurn
RATE=${FAULT_RATE:-0.5}
git diff --quiet HEAD -- "$OVERLAY" || { echo "$OVERLAY has uncommitted changes" >&2; exit 1; }

fault_env() { kubectl -n $NS get deploy shortener -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="FAULT_ERROR_RATE")].value}'; }
rolled_out() { # template has the value AND the rollout finished
  [[ $(fault_env) == "$1" ]] && kubectl -n $NS rollout status deploy/shortener --timeout=1s >/dev/null 2>&1
}

# ---- ship the bad release ----
yq -i '.patches += [{"patch": "apiVersion: apps/v1\nkind: Deployment\nmetadata: {name: shortener}\nspec:\n  template:\n    spec:\n      containers:\n        - name: shortener\n          env:\n            - {name: FAULT_ERROR_RATE, value: \"'"$RATE"'\"}\n"}]' "$OVERLAY"
git commit -q -m "release: shortener with FAULT_ERROR_RATE=$RATE (chaos day: a bad release)" -- "$OVERLAY"
bad_sha=$(git rev-parse --short HEAD)
log "bad-release: committed $bad_sha (FAULT_ERROR_RATE=$RATE), publishing"
make --no-print-directory publish >/dev/null
t0=$(now)

is_bad() { rolled_out "$RATE"; }
wait_for 600 "the bad release to roll out" -- is_bad >/dev/null
t_out=$(( $(now) - t0 ))
log "bad-release: rolled out at +${t_out}s (Argo CD sync + rolling update)"

pending() { [[ $(alert_state $ALERT) != inactive ]]; }
wait_for 3600 "$ALERT pending" -- pending >/dev/null
t_pending=$(( $(now) - t0 ))
log "bad-release: $ALERT pending at +${t_pending}s"
firing() { [[ $(alert_state $ALERT) == firing ]]; }
wait_for 600 "$ALERT firing" -- firing >/dev/null
t_page=$(( $(now) - t0 ))
log "bad-release: $ALERT FIRING at +${t_page}s (5m error ratio $(prom 'slo:sli_error:ratio_rate5m{slo="availability"}'), 1h $(prom 'slo:sli_error:ratio_rate1h{slo="availability"}'))"
in_am() { (( $(am_count $ALERT) > 0 )); }
wait_for 300 "Alertmanager to receive $ALERT" -- in_am >/dev/null
t_am=$(( $(now) - t0 ))
log "bad-release: Alertmanager has the page at +${t_am}s"

# ---- roll back: the runbook's first step ----
git revert --no-edit "$bad_sha" >/dev/null # that commit, whatever came after it
log "bad-release: git revert $bad_sha → $(git rev-parse --short HEAD), publishing"
make --no-print-directory publish >/dev/null
t_rb=$(now)
is_good() { rolled_out 0; }
wait_for 600 "the rollback to roll out" -- is_good >/dev/null
t_fixed=$(( $(now) - t_rb ))
log "bad-release: rollback rolled out ${t_fixed}s after the revert was published"

resolved() { [[ $(alert_state $ALERT) == inactive ]]; }
wait_for 3600 "$ALERT to resolve" -- resolved >/dev/null
t1=$(now)
t_resolved=$(( t1 - t_rb ))
log "bad-release: $ALERT resolved ${t_resolved}s after the revert was published"

client_bad=$(k6_window "$t0" "$t_rb")
client_after=$(k6_window "$t_rb" "$t1")
log "bad-release: client view, bad version live: $client_bad"
log "bad-release: client view, after the revert: $client_after"
record bad-release "$t0" "$t1" "bad=$bad_sha" "rollout_s=$t_out" "pending_s=$t_pending" "page_s=$t_page" \
  "alertmanager_s=$t_am" "rollback_rollout_s=$t_fixed" "resolved_after_revert_s=$t_resolved" \
  "bad:$client_bad" "after:$client_after"
