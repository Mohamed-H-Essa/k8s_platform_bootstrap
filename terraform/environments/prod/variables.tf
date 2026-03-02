variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "prod-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "node_groups" {
  description = "Node group configurations"
  type = map(object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size      = optional(number, 50)
    capacity_type  = optional(string, "ON_DEMAND")
    labels         = optional(map(string), {})
    taints         = optional(list(object({})), [])
  }))
  default = {
    general = {
      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 10
      desired_size   = 3
      disk_size      = 50
      labels = {
        workload = "general"
      }
    }
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "k8s-platform-bootstrap"
  }
}
