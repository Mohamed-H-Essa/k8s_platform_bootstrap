#!/usr/bin/env bash
# Show the supply-chain gate working: push an image nobody signed to the platform's
# registry and try to run it. Kyverno must refuse it at admission.
#
# The pod is otherwise compliant (version pinned, requests and limits, non-root), so the
# only thing wrong with it is the missing signature and SBOM attestation.
set -euo pipefail

IMAGE=${IMAGE:-busybox:1.37}
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull --quiet "$IMAGE" >/dev/null
docker tag "$IMAGE" localhost:5001/unsigned:1.37
docker push --quiet localhost:5001/unsigned:1.37 >/dev/null
echo "pushed an unsigned image: slipway-registry:5000/unsigned:1.37"
echo "trying to run it in namespace shortener..."

pod=$(cat <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: unsigned-demo
  namespace: shortener
spec:
  restartPolicy: Never
  securityContext: { runAsNonRoot: true, runAsUser: 65532 }
  containers:
    - name: demo
      image: slipway-registry:5000/unsigned:1.37
      command: [sleep, "60"]
      resources:
        requests: { cpu: 10m, memory: 16Mi }
        limits: { memory: 32Mi }
      securityContext: { allowPrivilegeEscalation: false }
YAML
)

if out=$(kubectl apply -f - <<<"$pod" 2>&1); then
  echo "$out"
  kubectl -n shortener delete pod unsigned-demo --wait=false >/dev/null 2>&1 || true
  echo "FAIL: the unsigned image was admitted" >&2
  exit 1
fi
echo
echo "$out" | sed 's/^/  /'
echo
if grep -q 'verify-platform-images' <<<"$out"; then
  echo "refused by Kyverno (verify-platform-images), as it should be"
else
  echo "refused, but not by the signature policy: check the message above" >&2
  exit 1
fi
