output "kubeconfig" {
  description = "kubeconfig for the cluster (the Makefile writes it to .local/kubeconfig)."
  value       = kind_cluster.this.kubeconfig
  sensitive   = true
}

output "endpoint" {
  value = kind_cluster.this.endpoint
}

output "urls" {
  value = {
    argocd    = "http://argocd.localtest.me"
    grafana   = "http://grafana.localtest.me"
    shortener = "http://sho.localtest.me"
    registry  = "localhost:5001"
    git       = "ssh://localhost:23231/platform.git"
  }
}
