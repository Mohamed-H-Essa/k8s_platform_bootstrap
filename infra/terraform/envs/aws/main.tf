# AWS environment: the same platform as envs/local, on EKS. Written and checked offline
# (validate, tflint, trivy config); never applied, there is no AWS account behind it.
# What it creates and what drives the cost: docs/aws.md.
#
#   VPC over 3 AZs, private subnets for nodes, one NAT gateway          modules/vpc
#   EKS (Kubernetes 1.35): on-demand "system" group + spot "apps"       modules/eks
#   group, the apps group scaled to zero at night, EBS CSI via Pod Identity
#   GitHub Actions role through OIDC (no stored keys)                   ci.tf
#   monthly budget with e-mail alerts                                   budget.tf
#   Argo CD + the root app (same chart and values as locally, env=aws)  argocd.tf

locals {
  repo_root = abspath("${path.module}/../../../..")
  tags = merge(var.tags, {
    project     = var.name
    environment = "aws"
    managed-by  = "terraform"
  })
}

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"] # skip Local Zones
  }
}

# Every new EBS volume in this region is encrypted (node disks, Postgres volumes), no
# matter who creates it.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

module "vpc" {
  source = "../../modules/vpc"

  name               = var.name
  cidr               = var.vpc_cidr
  azs                = slice(sort(data.aws_availability_zones.available.names), 0, 3)
  single_nat_gateway = var.single_nat_gateway
  tags               = local.tags
}

module "eks" {
  source = "../../modules/eks"

  name                   = var.name
  kubernetes_version     = var.kubernetes_version
  subnet_ids             = module.vpc.private_subnet_ids
  endpoint_public_access = true
  public_access_cidrs    = var.api_allowed_cidrs
  admin_principal_arns   = var.admin_principal_arns
  node_groups            = var.node_groups
  night_schedule         = var.night_schedule
  tags                   = local.tags

  depends_on = [aws_ebs_encryption_by_default.this]
}
