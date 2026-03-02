output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_version" {
  description = "EKS cluster version"
  value       = module.eks.cluster_version
}

output "kubectl_config" {
  description = "kubectl configuration command"
  value       = module.eks.kubectl_config
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.cluster_oidc_provider_arn
}

output "cluster_security_group_id" {
  description = "Cluster security group ID"
  value       = module.eks.cluster_security_group_id
}
