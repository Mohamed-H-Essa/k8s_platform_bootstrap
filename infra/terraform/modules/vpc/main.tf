# A VPC for EKS across N availability zones (3 by default):
#
#   public subnets   one per AZ, small (/24): only the NAT gateway and load balancers live here
#   private subnets  one per AZ, large (/19): the nodes and pods (the VPC CNI gives every pod a
#                    VPC address, so these need room)
#   NAT              one gateway for the whole VPC by default (cost); one per AZ if
#                    single_nat_gateway = false (no cross-AZ dependency, three times the cost)
#
# Cleaned up from the March 2026 module: for_each keyed by AZ (stable addresses when the AZ
# list changes), no public IPs on launch, the default security group locked down, and the
# subnet tags EKS needs to place load balancers.

locals {
  az_index = { for i, az in var.azs : az => i }

  # /16 → private /19s from the bottom (10.0.0.0/19, 10.0.32.0/19, …), public /24s from the top
  private_cidrs = { for az, i in local.az_index : az => cidrsubnet(var.cidr, 3, i) }
  public_cidrs  = { for az, i in local.az_index : az => cidrsubnet(var.cidr, 8, 240 + i) }

  # which AZs get a NAT gateway: the first one only, or all of them
  nat_azs = var.single_nat_gateway ? [var.azs[0]] : var.azs
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true # EKS nodes need DNS hostnames
  enable_dns_support   = true
  tags                 = merge(var.tags, { Name = var.name })
}

# The default security group allows all traffic between its members. Nothing should use
# it, so take every rule away (a CIS AWS benchmark control).
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-default-unused" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = var.name })
}

# ---- subnets ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = local.public_cidrs

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key
  # nothing gets a public IP by default: the NAT gateway has an Elastic IP and the load
  # balancers get their own addresses
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name                     = "${var.name}-public-${each.key}"
    "kubernetes.io/role/elb" = "1" # internet-facing load balancers go here
  })
}

resource "aws_subnet" "private" {
  for_each = local.private_cidrs

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(var.tags, {
    Name                              = "${var.name}-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1" # internal load balancers go here
  })
}

# ---- NAT: the nodes' way out (image pulls, AWS APIs) ----------------------------------
resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain     = "vpc"
  tags       = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })
  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })
  depends_on    = [aws_internet_gateway.this]
}

# ---- routing ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# one route table per AZ, so switching to a NAT gateway per AZ is a variable change
resource "aws_route_table" "private" {
  for_each = local.private_cidrs

  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-private-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each = local.private_cidrs

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? var.azs[0] : each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# S3 traffic (container image layers stored in S3, backups) skips the NAT gateway: a
# gateway endpoint has no hourly or per-GB charge, NAT data processing does.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]
  tags              = merge(var.tags, { Name = "${var.name}-s3" })
}

data "aws_region" "current" {}
