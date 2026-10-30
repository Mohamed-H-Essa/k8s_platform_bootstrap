#!/usr/bin/env bash
# End-to-end check through the gateway: create a short link, follow it, read its stats,
# and make sure the platform UIs answer.
set -euo pipefail

BASE=${BASE:-http://sho.localtest.me}
fails=0
ok()   { printf '  \033[32mok\033[0m    %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; fails=$((fails + 1)); }

target="https://example.com/smoke/$(date +%s)"
echo "shortener ($BASE)"
resp=$(curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
  -d "{\"url\":\"$target\"}" -w '\n%{http_code}' "$BASE/api/links" || true)
status=$(tail -n1 <<<"$resp")
body=$(sed '$d' <<<"$resp")
code=$(jq -r '.code // empty' <<<"$body" 2>/dev/null || true)
if [[ $status == 201 && -n $code ]]; then ok "POST /api/links → 201, code $code"; else fail "POST /api/links → $status $body"; fi

if [[ -n $code ]]; then
  read -r rstatus location < <(curl -sS --max-time 10 -o /dev/null -w '%{http_code} %{redirect_url}\n' "$BASE/$code" || true)
  if [[ $rstatus == 302 && $location == "$target" ]]; then ok "GET /$code → 302 $location"; else fail "GET /$code → $rstatus $location"; fi

  hits=$(curl -sS --max-time 10 "$BASE/api/links/$code" | jq -r '.hits' 2>/dev/null || true)
  if [[ $hits == 1 ]]; then ok "GET /api/links/$code → hits 1"; else fail "GET /api/links/$code → hits '$hits'"; fi
fi

echo "platform UIs"
check() { # name url expected-status...
  local name=$1 url=$2; shift 2
  local s; s=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "$url" || true)
  for want in "$@"; do [[ $s == "$want" ]] && { ok "$name → $s"; return; }; done
  fail "$name → $s (want $*)"
}
check "Grafana    http://grafana.localtest.me/api/health" http://grafana.localtest.me/api/health 200
check "Argo CD    http://argocd.localtest.me" http://argocd.localtest.me 200
check "Prometheus http://prometheus.localtest.me/-/ready" http://prometheus.localtest.me/-/ready 200

if (( fails )); then echo "smoke: $fails check(s) failed"; exit 1; fi
echo "smoke: all checks passed"
