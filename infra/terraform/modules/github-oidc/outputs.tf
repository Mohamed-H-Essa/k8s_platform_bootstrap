output "role_arn" {
  description = "ARN of the role: set it as the repository variable AWS_ROLE_ARN."
  value       = aws_iam_role.this.arn
}

output "provider_arn" {
  description = "ARN of the GitHub OIDC provider (one per account)."
  value       = aws_iam_openid_connect_provider.github.arn
}
