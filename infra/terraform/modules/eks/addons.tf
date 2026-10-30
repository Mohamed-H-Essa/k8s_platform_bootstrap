# EKS-managed add-ons. No versions pinned: EKS installs the default version for the
# cluster's Kubernetes version, and `aws eks describe-addon-versions` shows the upgrades.
#
# Two groups, because of ordering:
#   before nodes  the CNI (nodes can't turn Ready without it), kube-proxy and the Pod
#                 Identity agent (a DaemonSet that hands pods their IAM credentials)
#   after nodes   CoreDNS and the EBS CSI driver run as Deployments: created before any node
#                 exists they would sit in "Degraded" until the create times out

resource "aws_eks_addon" "before_nodes" {
  for_each = toset(["vpc-cni", "kube-proxy", "eks-pod-identity-agent"])

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = var.tags
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = var.tags

  depends_on = [aws_eks_node_group.this]
}

# ---- EBS CSI driver: persistent volumes (the Postgres cluster's disks) ------------------
# Its controller calls the EC2 API (create/attach volumes). It gets its own IAM role
# through EKS Pod Identity: the association below binds the role to exactly one service
# account in one cluster, so no other pod can use it, and no OIDC provider is needed.
data "aws_iam_policy_document" "pod_identity_assume" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "${local.policy_prefix}/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  pod_identity_association {
    role_arn        = aws_iam_role.ebs_csi.arn
    service_account = "ebs-csi-controller-sa"
  }

  # a default StorageClass (ebs-csi-default-sc; the driver's default volume type is gp3):
  # new EKS clusters no longer mark one as default, and the Postgres cluster's
  # PersistentVolumeClaims don't name a class. The env turns on EBS encryption by default,
  # so these disks are encrypted too.
  configuration_values = jsonencode({
    defaultStorageClass = { enabled = true }
  })

  tags = var.tags

  depends_on = [
    aws_eks_node_group.this,
    aws_eks_addon.before_nodes, # the Pod Identity agent
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}
