output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "github_actions_role_arn" {
  description = "Set as the repository variable AWS_ROLE_ARN (Settings → Secrets and variables → Actions → Variables)."
  value       = module.github_ci.role_arn
}

output "nat_public_ips" {
  description = "Outbound address(es) of the cluster."
  value       = module.vpc.nat_public_ips
}

output "node_group_asgs" {
  description = "Auto Scaling groups behind the node groups (the night schedule acts on these)."
  value       = module.eks.node_group_asgs
}

output "argocd_url" {
  description = "Argo CD, once DNS for the gateway's load balancer exists."
  value       = "https://argocd.${var.domain}"
}
