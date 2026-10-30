variable "name" {
  description = "Cluster name, also the prefix of its IAM roles, KMS alias and log group."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version (minor, e.g. \"1.35\")."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the nodes and the control plane's network interfaces (one per AZ)."
  type        = list(string)
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API on a public endpoint (limited to public_access_cidrs). The private endpoint is always on."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint (e.g. your own IP as x.x.x.x/32)."
  type        = list(string)

  validation {
    condition     = length(var.public_access_cidrs) > 0 && !contains(var.public_access_cidrs, "0.0.0.0/0")
    error_message = "List at least one CIDR, and not 0.0.0.0/0: the API should not be open to the internet."
  }
}

variable "enabled_log_types" {
  description = "Control plane log types sent to CloudWatch (api, audit, authenticator, controllerManager, scheduler)."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "log_retention_days" {
  description = "Days to keep control plane logs."
  type        = number
  default     = 7
}

variable "admin_principal_arns" {
  description = "Extra IAM roles/users that get cluster-admin through an access entry (the creator already has it)."
  type        = list(string)
  default     = []
}

variable "node_groups" {
  description = "Managed node groups, keyed by name."
  type = map(object({
    capacity_type       = string # ON_DEMAND or SPOT
    instance_types      = list(string)
    min_size            = number
    max_size            = number
    desired_size        = number
    disk_size_gib       = optional(number, 30)
    labels              = optional(map(string), {})
    scale_down_at_night = optional(bool, false)
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string # NO_SCHEDULE, NO_EXECUTE or PREFER_NO_SCHEDULE
    })), [])
  }))

  validation {
    condition     = alltrue([for g in values(var.node_groups) : contains(["ON_DEMAND", "SPOT"], g.capacity_type)])
    error_message = "capacity_type is ON_DEMAND or SPOT."
  }

  validation {
    condition     = alltrue([for g in values(var.node_groups) : g.min_size <= g.desired_size && g.desired_size <= g.max_size])
    error_message = "Each node group needs min_size <= desired_size <= max_size."
  }
}

variable "night_schedule" {
  description = "Scale node groups with scale_down_at_night to zero on a schedule (cron in time_zone, IANA name)."
  type = object({
    enabled   = bool
    time_zone = string
    down_cron = string
    up_cron   = string
  })
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
