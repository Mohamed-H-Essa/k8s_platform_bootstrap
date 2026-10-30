# An EKS cluster, private by default:
#
#   - nodes and the API's network interfaces sit in the private subnets
#   - the public API endpoint is open only to the CIDRs you list (no VPN or bastion in a lab)
#   - Kubernetes Secrets are envelope-encrypted with a customer-managed KMS key (rotated yearly)
#   - access is managed with EKS access entries (IAM → Kubernetes), not the aws-auth ConfigMap
#   - core add-ons (VPC CNI, kube-proxy, CoreDNS, Pod Identity, EBS CSI) are EKS-managed
#     add-ons, see addons.tf; node groups and the night schedule are in nodes.tf
#
# Started from the March 2026 module (cluster + IAM + node groups), then: access entries,
# KMS, standard support only (extended support costs more), AL2023 nodes with IMDSv2 and
# encrypted gp3 disks, Pod Identity instead of a cluster OIDC provider.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  policy_prefix = "arn:${data.aws_partition.current.partition}:iam::aws:policy"
}

# ---- secrets encryption ----------------------------------------------------------------
resource "aws_kms_key" "secrets" {
  description             = "${var.name}: envelope encryption of Kubernetes Secrets"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = var.tags
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name}-eks-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# ---- control plane logs ------------------------------------------------------------------
# created here (not by EKS) so the retention is ours: CloudWatch ingestion and storage cost money
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ---- the cluster's own IAM role ------------------------------------------------------------
data "aws_iam_policy_document" "cluster_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "${local.policy_prefix}/AmazonEKSClusterPolicy"
}

# ---- the cluster ---------------------------------------------------------------------------
# Accepted trivy finding AWS-0040 (public API endpoint): a lab has no VPN or bastion, so
# the endpoint stays public, but only for var.public_access_cidrs (0.0.0.0/0 is rejected).
#trivy:ignore:AWS-0040
resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  # VPC CNI, kube-proxy and CoreDNS come as managed add-ons (addons.tf), not as the
  # unmanaged copies EKS would otherwise install
  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode = "API"
    # whoever runs `terraform apply` becomes cluster admin (Terraform then installs Argo CD);
    # more admins: var.admin_principal_arns
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.secrets.arn
    }
  }

  enabled_cluster_log_types = var.enabled_log_types

  # standard support only: a version that falls into extended support is billed at a
  # higher hourly rate, so upgrades are forced instead
  upgrade_policy {
    support_type = "STANDARD"
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.cluster,
  ]
}

# ---- who may use the cluster -----------------------------------------------------------------
resource "aws_eks_access_entry" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "admin" {
  for_each = toset(var.admin_principal_arns)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.admin[each.key].principal_arn
  policy_arn    = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
