variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "ID of the VPC where the cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "cluster_enabled_log_types" {
  description = "List of EKS control plane logging types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to the cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to the cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks allowed to access the public cluster endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_groups" {
  description = "Map of EKS node group configurations"
  type = map(object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
    desired_size   = number
    disk_size      = optional(number, 50)
    capacity_type  = optional(string, "ON_DEMAND")
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    default = {
      instance_types = ["m5.large"]
      min_size       = 1
      max_size       = 10
      desired_size   = 3
    }
  }
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts (IRSA)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "encryption_config" {
  description = "Configuration for EKS encryption"
  type = object({
    provider_key_arn = string
    resources        = list(string)
  })
  default = null
}
