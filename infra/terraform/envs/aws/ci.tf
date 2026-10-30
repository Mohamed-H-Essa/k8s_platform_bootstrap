# GitHub Actions gets a role through OIDC, not access keys (modules/github-oidc).
#
# What CI needs on AWS is small: the platform deploys itself (Argo CD pulls from GitHub,
# the image comes from GHCR), so CI only checks that a release landed. Only runs on main
# of this repository may assume the role, and the role can:
#   - describe this one cluster (to build a kubeconfig), nothing else in AWS
#   - read (view) the shortener namespace in Kubernetes, nothing else in the cluster

data "aws_iam_policy_document" "ci" {
  statement {
    sid       = "DescribeThisClusterOnly"
    actions   = ["eks:DescribeCluster"]
    resources = [module.eks.cluster_arn]
  }
}

module "github_ci" {
  source = "../../modules/github-oidc"

  role_name   = "${var.name}-github-ci"
  subjects    = ["repo:${var.github_repository}:ref:refs/heads/main"]
  policy_json = data.aws_iam_policy_document.ci.json
  tags        = local.tags
}

resource "aws_eks_access_entry" "ci" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.github_ci.role_arn
  tags          = local.tags
}

resource "aws_eks_access_policy_association" "ci" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.ci.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["shortener"]
  }
}
