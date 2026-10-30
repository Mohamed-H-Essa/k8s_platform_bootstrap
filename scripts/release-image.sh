#!/usr/bin/env bash
# Build, scan, push, SBOM, sign and attest the shortener image. Prints the digest.
#
#   scripts/release-image.sh TAG
#
# The image is pushed through the host port (localhost:5001) but signed under the name
# the cluster pulls it by (slipway-registry:5000/shortener), so the signature's subject
# is exactly what Kyverno verifies. cosign v2 runs in a container on the kind network
# for that reason.
set -euo pipefail

TAG=${1:?usage: release-image.sh TAG}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCAL=$ROOT/.local
HOST_REPO=localhost:5001/shortener
CLUSTER_REPO=slipway-registry:5000/shortener
COSIGN_IMAGE=${COSIGN_IMAGE:-ghcr.io/sigstore/cosign/cosign:v2.4.1}
SBOM=$LOCAL/sbom-$TAG.spdx.json

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

step "build $HOST_REPO:$TAG"
docker build --quiet --build-arg VERSION="$TAG" -t "$HOST_REPO:$TAG" "$ROOT/app" >/dev/null
docker image ls "$HOST_REPO:$TAG" --format '{{.Repository}}:{{.Tag}}  {{.Size}}'

step "scan (Trivy: fail on fixable HIGH/CRITICAL)"
trivy image --quiet --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed "$HOST_REPO:$TAG"
echo "no fixable HIGH/CRITICAL vulnerabilities"

step "push"
docker push --quiet "$HOST_REPO:$TAG" >/dev/null
# the digest the registry serves for this tag (what Kyverno resolves the tag to)
DIGEST=$(curl -fsSI \
  -H 'Accept: application/vnd.oci.image.index.v1+json' \
  -H 'Accept: application/vnd.oci.image.manifest.v1+json' \
  -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
  -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
  "http://localhost:5001/v2/shortener/manifests/$TAG" |
  awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}' | tr -d '\r')
[[ $DIGEST == sha256:* ]] || { echo "could not read the digest of $TAG" >&2; exit 1; }
echo "$CLUSTER_REPO@$DIGEST"

step "SBOM (Syft, SPDX JSON)"
syft scan --quiet "docker:$HOST_REPO:$TAG" -o "spdx-json=$SBOM"
echo "$(jq '.packages | length' "$SBOM") packages → ${SBOM#"$ROOT"/}"

# cosign v2, on the kind network, with the local key. No transparency log: this
# registry and key never leave the laptop (CI signs keyless, with Rekor, instead).
cosign() {
  docker run --rm --network kind --user "$(id -u)" \
    -v "$LOCAL:/work:ro" -e COSIGN_PASSWORD= \
    "$COSIGN_IMAGE" "$@" --key /work/cosign.key --allow-http-registry --tlog-upload=false --yes
}

step "sign"
cosign sign "$CLUSTER_REPO@$DIGEST"

step "attest the SBOM"
cosign attest --type spdxjson --predicate "/work/$(basename "$SBOM")" "$CLUSTER_REPO@$DIGEST"

step "done: $TAG"
echo "$DIGEST"
