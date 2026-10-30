#!/usr/bin/env bash
# Render everything Argo CD would apply and validate it offline, no cluster needed:
#   - the app of apps (platform/apps) for every environment
#   - every Kustomize directory under platform/
# against the Kubernetes schemas for KUBE_VERSION and the CRD schemas of the datreeio
# catalog (Argo CD, Gateway API, Envoy Gateway, Kyverno, Prometheus, CloudNativePG, …).
# Resources whose kind has no schema anywhere are counted as "Skipped" in the summary.
set -euo pipefail
cd "$(dirname "$0")/.."

KUBE_VERSION="${KUBE_VERSION:-1.35.0}"
CACHE="${KUBECONFORM_CACHE:-.local/kubeconform-cache}" # schemas are downloaded once
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
mkdir -p "$CACHE"

# validate NAME < manifests
validate() {
  printf '%-44s ' "$1"
  kubeconform -strict -ignore-missing-schemas -summary \
    -kubernetes-version "$KUBE_VERSION" -cache "$CACHE" \
    -schema-location default -schema-location "$CRD_SCHEMAS" -
}

for env in local aws; do
  helm template root platform/apps --namespace argocd --set env="$env" |
    validate "platform/apps (env=$env)"
done

while read -r dir; do
  kubectl kustomize "$dir" | validate "$dir"
done < <(find platform -name kustomization.yaml -exec dirname {} \; | sort)

echo "manifests: OK"
