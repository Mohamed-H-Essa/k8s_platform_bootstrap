# Argo CD and the root application, exactly as envs/local does it: the same chart, the
# same platform/values/argocd.yaml, the same app of apps (platform/apps). Only three
# values change: Argo CD reads GitHub instead of the local Git server, and env=aws picks
# platform/values/aws/*.yaml and the shortener's aws overlay (image from GHCR).

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  values = [
    file("${local.repo_root}/platform/values/argocd.yaml"),
    yamlencode({ global = { domain = "argocd.${var.domain}" } }),
  ]
  wait    = true
  timeout = 900

  # nodes, CoreDNS and the storage driver first, not just the control plane
  depends_on = [module.eks]
}

# The one Application Terraform creates; everything else is in Git (platform/apps).
resource "helm_release" "root" {
  name       = "root"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  values = [yamlencode({
    applications = {
      root = {
        namespace  = "argocd"
        project    = "default"
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        source = {
          repoURL        = var.git_repo_url
          targetRevision = var.git_revision
          path           = "platform/apps"
          # the app of apps is a Helm chart: these values reach every child Application
          helm = {
            valuesObject = {
              repoURL  = var.git_repo_url
              revision = var.git_revision
              env      = "aws"
            }
          }
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "argocd" }
        syncPolicy = {
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
          retry       = { limit = 10, backoff = { duration = "10s", factor = 2, maxDuration = "3m" } }
        }
      }
    }
  })]
  depends_on = [helm_release.argocd]
}
