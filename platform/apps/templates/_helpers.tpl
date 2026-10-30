{{/* Shared Application spec: automated sync, self-heal, retries. Server-side apply
     because some CRDs (Prometheus, Kyverno) are too big for client-side apply. */}}
{{- define "slipway.sync" -}}
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
    - SkipDryRunOnMissingResource=true
  retry:
    limit: 10
    backoff: { duration: 15s, factor: 2, maxDuration: 3m }
{{- end -}}

{{/* A Helm chart from an upstream repo, with values from this repo (common + env). */}}
{{- define "slipway.helmApp" -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: {{ .wave | quote }}
  finalizers: [resources-finalizer.argocd.argoproj.io]
spec:
  project: default
  sources:
    - repoURL: {{ .repo }}
      chart: {{ .chart }}
      targetRevision: {{ .version | quote }}
      helm:
        releaseName: {{ .release | default .name }}
        ignoreMissingValueFiles: true
        valueFiles:
          - $values/platform/values/{{ .name }}.yaml
          - $values/platform/values/{{ .root.Values.env }}/{{ .name }}.yaml
    - repoURL: {{ .root.Values.repoURL }}
      targetRevision: {{ .root.Values.revision }}
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ .namespace }}
  {{- include "slipway.sync" . | nindent 2 }}
{{- end -}}

{{/* Plain manifests (Kustomize) from a directory of this repo. Compared with a
     server-side dry run, so fields the API server fills in (Gateway API defaults, the
     digest Kyverno pins) are not reported as drift. Only here: on the big upstream charts
     a dry run per resource per refresh costs more CPU than a laptop has. */}}
{{- define "slipway.dirApp" -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: {{ .wave | quote }}
    argocd.argoproj.io/compare-options: ServerSideDiff=true
  finalizers: [resources-finalizer.argocd.argoproj.io]
spec:
  project: default
  source:
    repoURL: {{ .root.Values.repoURL }}
    targetRevision: {{ .root.Values.revision }}
    path: {{ .path }}
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ .namespace }}
  {{- include "slipway.sync" . | nindent 2 }}
{{- end -}}
