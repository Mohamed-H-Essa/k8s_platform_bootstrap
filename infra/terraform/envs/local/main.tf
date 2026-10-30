# Local environment: the whole platform on a laptop, no cloud account.
#
#   kind cluster (1 control plane + 2 workers, Kubernetes in Docker)
#   + an OCI registry for the platform's own images      slipway-registry:5000 (host: localhost:5001)
#   + pull-through caches for docker.io, quay.io, ghcr.io and registry.k8s.io, so every
#     image is downloaded once and recreating the cluster is fast
#   + a Git server (soft-serve) that plays GitHub: ArgoCD syncs from it
#   + Argo CD itself and the root Application ("app of apps")
#
# Everything sits on the "kind" Docker network, so the nodes reach the registry, the
# caches and the Git server by container name. Caches and the registry keep their data
# in named volumes created by the Makefile, so `make down` leaves them warm.

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    kind   = { source = "tehcyx/kind", version = "~> 0.9" }
    docker = { source = "kreuzwerker/docker", version = "~> 3.6" }
    helm   = { source = "hashicorp/helm", version = "~> 2.17" }
  }
}

provider "docker" {
  host = var.docker_host
}

provider "helm" {
  kubernetes {
    host                   = kind_cluster.this.endpoint
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
  }
}

locals {
  repo_root = abspath("${path.module}/../../../..")
  # upstream registry → the cache container that stands in front of it
  mirrors = {
    "docker.io"       = { name = "slipway-cache-dockerio", port = 5101, remote = "https://registry-1.docker.io" }
    "quay.io"         = { name = "slipway-cache-quayio", port = 5102, remote = "https://quay.io" }
    "ghcr.io"         = { name = "slipway-cache-ghcrio", port = 5103, remote = "https://ghcr.io" }
    "registry.k8s.io" = { name = "slipway-cache-k8sio", port = 5104, remote = "https://registry.k8s.io" }
  }
}

# ---- the cluster ---------------------------------------------------------------
resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # containerd looks up per-registry hosts.toml files here (see containerd/certs.d):
    # that is where docker.io → the cache, and slipway-registry:5000 → plain HTTP, are set.
    # kind's node image still writes a version 2 containerd config, hence the v2 key.
    containerd_config_patches = [
      <<-TOML
      [plugins."io.containerd.grpc.v1.cri".registry]
        config_path = "/etc/containerd/certs.d"
      TOML
    ]

    node {
      role = "control-plane"
      # etcd without fsync: on this laptop's virtual disk a WAL fsync averaged ~50 ms and a
      # commit ~100 ms (healthy is < 10 ms), so the API server stalled, leader elections
      # timed out and controllers restarted in a loop. A throwaway local cluster does not
      # need crash-safe etcd; a real one does (and gets it on EKS).
      kubeadm_config_patches = [
        <<-YAML
        kind: ClusterConfiguration
        etcd:
          local:
            extraArgs:
              unsafe-no-fsync: "true"
        YAML
      ]
      # host :80 → the Envoy Gateway NodePort: http://*.localtest.me reaches the cluster
      extra_port_mappings {
        container_port = 30080
        host_port      = var.http_port
        listen_address = "127.0.0.1"
      }
      extra_mounts {
        host_path      = "${local.repo_root}/infra/terraform/envs/local/containerd/certs.d"
        container_path = "/etc/containerd/certs.d"
        read_only      = true
      }
    }

    dynamic "node" {
      for_each = toset(["a", "b"])
      content {
        role   = "worker"
        labels = { "slipway.dev/pool" = "apps", "slipway.dev/zone" = "zone-${node.value}" }
        extra_mounts {
          host_path      = "${local.repo_root}/infra/terraform/envs/local/containerd/certs.d"
          container_path = "/etc/containerd/certs.d"
          read_only      = true
        }
      }
    }
  }
}

# ---- registry, caches and Git server, on the kind network -------------------------
resource "docker_image" "registry" {
  name         = "registry:2.8.3"
  keep_locally = true
}

resource "docker_container" "registry" {
  name    = "slipway-registry"
  image   = docker_image.registry.image_id
  restart = "unless-stopped"
  ports {
    internal = 5000
    external = 5001
    ip       = "127.0.0.1"
  }
  volumes {
    volume_name    = "slipway-registry-data"
    container_path = "/var/lib/registry"
  }
  networks_advanced { name = "kind" }
  depends_on = [kind_cluster.this]
  # some engines (OrbStack) add default log options; don't recreate the container for that
  lifecycle { ignore_changes = [log_opts] }
}

resource "docker_container" "cache" {
  for_each = local.mirrors
  name     = each.value.name
  image    = docker_image.registry.image_id
  restart  = "unless-stopped"
  env      = ["REGISTRY_PROXY_REMOTEURL=${each.value.remote}"]
  ports {
    internal = 5000
    external = each.value.port
    ip       = "127.0.0.1"
  }
  volumes {
    volume_name    = "${each.value.name}-data"
    container_path = "/var/lib/registry"
  }
  networks_advanced { name = "kind" }
  depends_on = [kind_cluster.this]
  # some engines (OrbStack) add default log options; don't recreate the container for that
  lifecycle { ignore_changes = [log_opts] }
}

resource "docker_image" "git" {
  name         = var.git_server_image
  keep_locally = true
}

resource "docker_container" "git" {
  name    = "slipway-git"
  image   = docker_image.git.image_id
  restart = "unless-stopped"
  env = [
    "SOFT_SERVE_INITIAL_ADMIN_KEYS=${trimspace(file(var.git_admin_public_key))}",
    "SOFT_SERVE_HTTP_PUBLIC_URL=http://slipway-git:23232",
  ]
  ports {
    internal = 23231 # ssh: the Makefile pushes here
    external = 23231
    ip       = "127.0.0.1"
  }
  ports {
    internal = 23232 # http: Argo CD pulls from here
    external = 23232
    ip       = "127.0.0.1"
  }
  volumes {
    volume_name    = "slipway-git-data"
    container_path = "/soft-serve"
  }
  networks_advanced { name = "kind" }
  depends_on = [kind_cluster.this]
  # some engines (OrbStack) add default log options; don't recreate the container for that
  lifecycle { ignore_changes = [log_opts] }
}

# ---- Argo CD and the root application ----------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  values           = [file("${local.repo_root}/platform/values/argocd.yaml")]
  wait             = true
  timeout          = 900
  depends_on       = [docker_container.cache]
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
          directory      = { recurse = false }
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
  depends_on = [helm_release.argocd, docker_container.git]
}
