resource "aws_vpc" "main" {
  cidr_block           = var.cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(
    var.tags,
    {
      Name = var.name
    }
  )
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-igw"
    }
  )
}

# Public subnets
resource "aws_subnet" "public" {
  count = length(var.public_subnets)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    var.public_subnet_tags,
    {
      Name = "${var.name}-public-${var.azs[count.index]}"
      Type = "public"
    }
  )
}

# Private subnets
resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    var.private_subnet_tags,
    {
      Name = "${var.name}-private-${var.azs[count.index]}"
      Type = "private"
    }
  )
}

# NAT Gateway
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway && !var.single_nat_gateway ? length(var.azs) : var.enable_nat_gateway ? 1 : 0

  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-nat-eip-${var.azs[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway && !var.single_nat_gateway ? length(var.azs) : var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-nat-${var.azs[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-public-rt"
    }
  )
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table" "private" {
  count = var.enable_nat_gateway && !var.single_nat_gateway ? length(var.azs) : 1

  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-private-rt-${count.index}"
    }
  )
}

resource "aws_route" "private_nat_gateway" {
  count = var.enable_nat_gateway && !var.single_nat_gateway ? length(var.azs) : var.enable_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}

# Route table associations
resource "aws_route_table_association" "public" {
  count = length(var.public_subnets)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnets)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}

# VPC Endpoint for S3 (optional but recommended for EKS)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-s3-endpoint"
    }
  )
}

data "aws_region" "current" {}
