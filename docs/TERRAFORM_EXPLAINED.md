# Terraform Modules Explained

This guide explains every Terraform module in detail, line by line.

## Module Structure

```
terraform/
├── modules/              # Reusable building blocks
│   ├── vpc/             # Creates network infrastructure
│   └── eks/             # Creates Kubernetes cluster
└── environments/        # Environment-specific configs
    └── prod/            # Production deployment
```

## VPC Module (`modules/vpc/`)

The VPC module creates a complete network infrastructure in AWS.

### File: `variables.tf` - Input Parameters

```hcl
# What is a variable?
# Variables are inputs that make modules configurable and reusable.
# Instead of hardcoding values, we accept them as parameters.

variable "name" {
  description = "Name to be used on all resources as prefix"
  type        = string
  # This creates a required variable - no default value
}

variable "cidr" {
  description = "The CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  # Default means this value is optional
  # CIDR = Classless Inter-Domain Routing (IP address range)
}

variable "azs" {
  description = "List of availability zones"
  type        = list(string)
  # List of strings, e.g., ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  # These are private IP ranges within the VPC
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
  # NAT Gateway allows private subnets to access internet (outbound only)
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway for all private subnets"
  type        = bool
  default     = false
  # false = one NAT Gateway per AZ (more expensive, more available)
  # true = one NAT Gateway total (cheaper, single point of failure)
}
```

**Key Concepts**:
- **CIDR Block**: A range of IP addresses (10.0.0.0/16 = 65,536 addresses)
- **Availability Zone (AZ)**: Physical data center in a region
- **Subnet**: Subdivision of a VPC, lives in one AZ
- **Public Subnet**: Has internet access via Internet Gateway
- **Private Subnet**: No direct internet access, uses NAT Gateway

### File: `main.tf` - Resource Creation

```hcl
# VPC - Virtual Private Cloud
# This is your own private network in AWS
resource "aws_vpc" "main" {
  cidr_block           = var.cidr          # IP range for the VPC
  enable_dns_hostnames = var.enable_dns_hostnames  # Assign DNS hostnames
  enable_dns_support   = var.enable_dns_support    # Enable DNS resolution

  tags = merge(
    var.tags,  # Tags passed in as variable
    {
      Name = var.name  # Add a Name tag
    }
  )
}
```

**What this does**:
- Creates a virtual network in AWS
- CIDR block 10.0.0.0/16 gives you 65,536 private IP addresses
- Enables DNS so instances can resolve domain names

```hcl
# Internet Gateway
# This allows public subnets to communicate with the internet
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id  # Attach to the VPC we just created

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-igw"
    }
  )
}
```

**What this does**:
- Creates an Internet Gateway (like a router)
- Attaches it to your VPC
- Required for public subnets to reach the internet

```hcl
# Public Subnets
# Subnets that have direct internet access
resource "aws_subnet" "public" {
  count = length(var.public_subnets)  # Create one subnet per CIDR block

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.azs[count.index]  # One per AZ
  map_public_ip_on_launch = true  # Automatically assign public IPs

  tags = merge(
    var.tags,
    var.public_subnet_tags,
    {
      Name = "${var.name}-public-${var.azs[count.index]}"
      Type = "public"
    }
  )
}
```

**What this does**:
- Creates multiple public subnets (one per AZ)
- Each subnet gets its own CIDR block from the list
- Instances automatically get public IP addresses

```hcl
# Private Subnets
# Subnets without direct internet access (more secure)
resource "aws_subnet" "private" {
  count = length(var.private_subnets)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = false  # No public IPs

  tags = merge(
    var.tags,
    var.private_subnet_tags,
    {
      Name = "${var.name}-private-${var.azs[count.index]}"
      Type = "private"
    }
  )
}
```

**What this does**:
- Creates multiple private subnets (one per AZ)
- No public IP addresses (more secure)
- Worker nodes go here

```hcl
# NAT Gateway - Elastic IP
# NAT Gateways need a static public IP address
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway && !var.single_nat_gateway ? length(var.azs) : var.enable_nat_gateway ? 1 : 0
  # This condition determines how many EIPs to create:
  # - If NAT Gateway enabled and not single: one per AZ
  # - If NAT Gateway enabled and single: just one
  # - If NAT Gateway disabled: zero

  domain = "vpc"  # EIP is in VPC domain

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-nat-eip-${var.azs[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.main]
  # Must wait for Internet Gateway to be created first
}
```

**What this does**:
- Allocates Elastic IP addresses (static public IPs)
- One per NAT Gateway
- These are fixed IPs that don't change

```hcl
# NAT Gateway
# Allows private subnets to access the internet (outbound only)
resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway && !var.single_nat_gateway ? length(var.azs) : var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[count.index].id  # Use the EIP we created
  subnet_id     = aws_subnet.public[count.index].id  # NAT lives in public subnet

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-nat-${var.azs[count.index]}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}
```

**What this does**:
- Creates NAT Gateway(s) for internet access from private subnets
- Outbound only (private instances can access internet, but internet can't reach them)
- Cost: ~$32/month per NAT Gateway

```hcl
# Route Tables
# Define how network traffic is routed

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-public-rt"
    }
  )
}

# Route to Internet Gateway
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"  # All traffic
  gateway_id             = aws_internet_gateway.main.id  # To internet
}
```

**What this does**:
- Creates a routing table for public subnets
- Routes all internet traffic (0.0.0.0/0) to Internet Gateway

```hcl
# Private Route Tables (one per AZ)
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

# Route to NAT Gateway
resource "aws_route" "private_nat_gateway" {
  count = var.enable_nat_gateway && !var.single_nat_gateway ? length(var.azs) : var.enable_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}
```

**What this does**:
- Creates routing tables for private subnets
- Routes internet traffic through NAT Gateway

```hcl
# Route Table Associations
# Connect subnets to route tables

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
```

**What this does**:
- Associates each subnet with its route table
- Determines how traffic flows from each subnet

```hcl
# VPC Endpoint for S3
# Allows private subnets to access S3 without going through internet
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"  # Gateway type is free!

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

data "aws_region" "current" {}  # Fetches current AWS region
```

**What this does**:
- Creates a private connection to S3
- No internet needed to access S3
- More secure and faster
- Gateway endpoints are free!

### File: `outputs.tf` - Export Values

```hcl
# Outputs expose values that other modules or the root module can use

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
  # This is used by other modules (like EKS) to know which VPC to use
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = aws_subnet.public[*].id
  # Used for load balancers that need public access
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = aws_subnet.private[*].id
  # Used for worker nodes (more secure)
}
```

**What outputs do**:
- Export values for use by other modules
- Can be referenced: `module.vpc.vpc_id`
- Can be viewed: `terraform output`

### Visual Representation

```
VPC (10.0.0.0/16)
│
├── Internet Gateway
│
├── Public Subnets (AZ-1, AZ-2, AZ-3)
│   ├── Route Table: 0.0.0.0/0 → Internet Gateway
│   └── Resources: NAT Gateway, Load Balancers
│
├── Private Subnets (AZ-1, AZ-2, AZ-3)
│   ├── Route Table: 0.0.0.0/0 → NAT Gateway
│   └── Resources: EKS Worker Nodes
│
└── VPC Endpoints
    └── S3 Gateway Endpoint
```

## EKS Module (`modules/eks/`)

The EKS module creates a managed Kubernetes cluster.

### File: `variables.tf`

```hcl
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.28"
  # Kubernetes versions: 1.27, 1.28, 1.29, etc.
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
  # Usually private subnets for security
}

variable "node_groups" {
  description = "Map of EKS node group configurations"
  type = map(object({
    instance_types = list(string)  # e.g., ["m5.large"]
    min_size       = number        # Minimum nodes
    max_size       = number        # Maximum nodes
    desired_size   = number        # Target nodes
    disk_size      = optional(number, 50)  # GB
    capacity_type  = optional(string, "ON_DEMAND")  # or SPOT
    labels         = optional(map(string), {})  # K8s labels
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string  # NoSchedule, PreferNoSchedule, NoExecute
    })), [])
  }))
  # Map allows multiple node groups with different purposes
}
```

### File: `main.tf` - Key Resources

```hcl
# EKS Cluster
# The control plane of Kubernetes
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn  # IAM role for cluster

  vpc_config {
    subnet_ids              = var.subnet_ids  # Where to place cluster
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
    security_group_ids      = [aws_security_group.cluster.id]
  }

  enabled_cluster_log_types = var.cluster_enabled_log_types
  # Logs: api, audit, authenticator, controllerManager, scheduler

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_cloudwatch_log_group.eks_cluster,
  ]
}
```

**What this does**:
- Creates EKS control plane (managed by AWS)
- Configures network access
- Enables logging
- Associates IAM role

```hcl
# Node Groups
# The worker nodes that run your applications
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups  # Create one node group per entry

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key  # Name from map key
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.subnet_ids

  instance_types = each.value.instance_types
  capacity_type  = each.value.capacity_type  # ON_DEMAND or SPOT
  disk_size      = each.value.disk_size

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  labels = merge(
    each.value.labels,
    {
      NodeGroup = each.key
    }
  )

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
    # Allow cluster autoscaler to modify desired_size without Terraform reverting it
  }
}
```

**What this does**:
- Creates worker nodes (EC2 instances)
- Configures auto-scaling
- Applies Kubernetes labels
- Allows cluster autoscaler to manage node count

## Production Environment (`environments/prod/`)

This directory uses the modules to create a production cluster.

### File: `main.tf`

```hcl
# Use the VPC module
module "vpc" {
  source = "../../modules/vpc"  # Path to module

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = var.availability_zones

  # Dynamically create subnet CIDRs
  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i)]
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  enable_nat_gateway = true
  single_nat_gateway = false  # One per AZ for HA

  # Tags required for EKS/AWS Load Balancer Controller
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1  # For public load balancers
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1  # For internal load balancers
  }

  tags = var.tags
}

# Use the EKS module
module "eks" {
  source = "../../modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id  # Reference VPC output
  subnet_ids      = module.vpc.private_subnet_ids  # Reference VPC output

  node_groups = var.node_groups

  enable_irsa = true  # Enable IAM Roles for Service Accounts

  tags = var.tags
}
```

**What this does**:
- Uses modules as building blocks
- Passes outputs from VPC as inputs to EKS
- Creates a complete production setup

### The Deployment Flow

```
1. terraform init
   └── Downloads providers and modules

2. terraform plan
   └── Shows what will be created:
       - VPC (1)
       - Subnets (6)
       - Internet Gateway (1)
       - NAT Gateways (3)
       - EIPs (3)
       - Route Tables (4)
       - EKS Cluster (1)
       - Node Groups (1-3)
       - IAM Roles (2)
       - Security Groups (1)

3. terraform apply
   └── Creates everything (~10-12 minutes)
```

## Best Practices Used

1. **Modular Design**: Reusable modules
2. **Naming Convention**: Consistent prefixes
3. **Tagging**: All resources tagged
4. **High Availability**: Multi-AZ deployment
5. **Security**: Private subnets for workers
6. **Scalability**: Auto-scaling node groups
7. **Observability**: Cluster logging enabled

## Common Commands

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Format code
terraform fmt

# Plan changes
terraform plan

# Apply changes
terraform apply

# View outputs
terraform output

# Destroy infrastructure
terraform destroy
```

## Next Steps

- Read [KUBERNETES_MANIFESTS_EXPLAINED.md](KUBERNETES_MANIFESTS_EXPLAINED.md) to understand the Kubernetes configurations
- Read [ARGOCD_EXPLAINED.md](ARGOCD_EXPLAINED.md) to understand GitOps setup
