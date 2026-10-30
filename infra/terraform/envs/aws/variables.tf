# ---- you must set these (terraform.tfvars, see terraform.tfvars.example) ---------------
variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API's public endpoint, e.g. [\"<your IP>/32\"]."
  type        = list(string)
}

variable "budget_email" {
  description = "Where budget alerts go."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_email))
    error_message = "budget_email must be an e-mail address."
  }
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD: alerts at 80 % actual and 100 % forecast."
  type        = number

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be positive."
  }
}

# ---- defaults you may change -------------------------------------------------------------
variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "name" {
  description = "Name of the cluster and prefix of everything else."
  type        = string
  default     = "slipway"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version, the same minor as the local kind cluster."
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "VPC CIDR (/16)."
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "One NAT gateway (cheaper; its AZ is a single point of failure for outbound traffic) or one per AZ."
  type        = bool
  default     = true
}

variable "admin_principal_arns" {
  description = "Extra IAM principals that get cluster-admin (whoever applies is admin already)."
  type        = list(string)
  default     = []
}

variable "node_groups" {
  description = "Managed node groups (see modules/eks). The shortener runs on nodes labelled slipway.dev/pool=apps, as locally."
  type = map(object({
    capacity_type       = string
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
      effect = string
    })), [])
  }))
  default = {
    # on-demand, always on: Argo CD, the operators and the observability stack keep
    # running at night, so mornings only start pods
    system = {
      capacity_type  = "ON_DEMAND"
      instance_types = ["t3.large"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1
      labels         = { "slipway.dev/pool" = "system" }
    }
    # spot, several interchangeable 2 vCPU / 8 GiB types so one type running out of spot
    # capacity doesn't empty the group; scaled to zero at night
    apps = {
      capacity_type       = "SPOT"
      instance_types      = ["m6i.large", "m6a.large", "m5.large", "m5a.large", "m7i.large"]
      min_size            = 2
      max_size            = 4
      desired_size        = 2
      labels              = { "slipway.dev/pool" = "apps" }
      scale_down_at_night = true
    }
  }
}

variable "night_schedule" {
  description = "When groups with scale_down_at_night go to zero and come back (cron, in time_zone)."
  type = object({
    enabled   = bool
    time_zone = string
    down_cron = string
    up_cron   = string
  })
  default = {
    enabled   = true
    time_zone = "UTC"
    down_cron = "0 20 * * *"  # every evening at 20:00
    up_cron   = "0 7 * * 1-5" # weekday mornings at 07:00, so weekends stay off
  }
}

variable "github_repository" {
  description = "owner/name of the repository whose main branch may assume the CI role."
  type        = string
  default     = "Mohamed-H-Essa/k8s_platform_bootstrap"
}

variable "git_repo_url" {
  description = "Where Argo CD reads the platform from."
  type        = string
  default     = "https://github.com/Mohamed-H-Essa/k8s_platform_bootstrap.git"
}

variable "git_revision" {
  description = "Branch, tag or commit Argo CD follows."
  type        = string
  default     = "main"
}

variable "domain" {
  description = "DNS zone for the platform's hostnames (argocd.<domain>, sho.<domain>)."
  type        = string
  default     = "example.com"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version (the same as envs/local)."
  type        = string
  default     = "10.11.6"
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps Helm chart version (the same as envs/local)."
  type        = string
  default     = "2.0.7"
}

variable "tags" {
  description = "Extra tags for every resource (project, environment and managed-by are always set)."
  type        = map(string)
  default     = {}
}
