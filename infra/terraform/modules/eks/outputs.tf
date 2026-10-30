output "cluster_name" {
  description = "Cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "Cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "certificate_authority_data" {
  description = "Base64 CA certificate of the API endpoint."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "node_role_arn" {
  description = "IAM role of the nodes."
  value       = aws_iam_role.node.arn
}

output "node_group_asgs" {
  description = "Auto Scaling group behind each node group (the night schedule acts on these)."
  value       = { for k, ng in aws_eks_node_group.this : k => ng.resources[0].autoscaling_groups[0].name }
}

output "secrets_kms_key_arn" {
  description = "KMS key that encrypts Kubernetes Secrets."
  value       = aws_kms_key.secrets.arn
}

output "account_id" {
  description = "AWS account the cluster lives in."
  value       = data.aws_caller_identity.current.account_id
}
