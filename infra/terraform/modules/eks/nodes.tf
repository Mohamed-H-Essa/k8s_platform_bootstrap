# Managed node groups (one per entry in var.node_groups) and their night schedule.
#
# Every group gets a launch template for two things the defaults don't give: IMDSv2 only,
# with a hop limit of 1 (pods can't reach the node's instance credentials; they get their
# own through Pod Identity), and an encrypted gp3 root disk. No AMI and no security group
# in the template: EKS picks the AL2023 image for the cluster version and attaches the
# cluster security group.

# ---- the nodes' IAM role -------------------------------------------------------------------
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "AmazonEKSWorkerNodePolicy",
    # the VPC CNI runs on every node before anything else can: it keeps the node role's
    # permissions so nodes can join without depending on Pod Identity being up first
    "AmazonEKS_CNI_Policy",
    # pull only (no list/describe): add-on images come from ECR
    "AmazonEC2ContainerRegistryPullOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = "${local.policy_prefix}/${each.value}"
}

# ---- launch templates ------------------------------------------------------------------------
resource "aws_launch_template" "node" {
  for_each = var.node_groups

  name_prefix            = "${var.name}-${each.key}-"
  description            = "${var.name} ${each.key} nodes: IMDSv2 only, encrypted gp3 root disk"
  update_default_version = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda" # the AL2023 root device
    ebs {
      volume_size           = each.value.disk_size_gib
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-${each.key}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, { Name = "${var.name}-${each.key}" })
  }

  tags = var.tags
}

# ---- node groups -----------------------------------------------------------------------------
resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types

  launch_template {
    id      = aws_launch_template.node[each.key].id
    version = aws_launch_template.node[each.key].latest_version
  }

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = var.tags

  lifecycle {
    # the night schedule (and any autoscaler) changes the size: don't fight it on every plan
    ignore_changes = [scaling_config[0].desired_size]
  }

  # nodes only turn Ready once the CNI runs; the agents must exist before the first node
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_nodes,
  ]
}

# ---- night schedule --------------------------------------------------------------------------
# A managed node group is an EC2 Auto Scaling group underneath. Scheduled actions on that
# group take it to zero in the evening and back in the morning (weekdays). The control
# plane and the NAT gateway still bill at night; only the instances stop.
locals {
  night_groups = { for k, v in var.node_groups : k => v if v.scale_down_at_night && var.night_schedule.enabled }
}

resource "aws_autoscaling_schedule" "night_down" {
  for_each = local.night_groups

  scheduled_action_name  = "${var.name}-${each.key}-night-down"
  autoscaling_group_name = aws_eks_node_group.this[each.key].resources[0].autoscaling_groups[0].name
  recurrence             = var.night_schedule.down_cron
  time_zone              = var.night_schedule.time_zone
  min_size               = 0
  max_size               = each.value.max_size # still allows a manual scale-up at night
  desired_capacity       = 0
}

resource "aws_autoscaling_schedule" "morning_up" {
  for_each = local.night_groups

  scheduled_action_name  = "${var.name}-${each.key}-morning-up"
  autoscaling_group_name = aws_eks_node_group.this[each.key].resources[0].autoscaling_groups[0].name
  recurrence             = var.night_schedule.up_cron
  time_zone              = var.night_schedule.time_zone
  min_size               = each.value.min_size
  max_size               = each.value.max_size
  desired_capacity       = each.value.desired_size
}
