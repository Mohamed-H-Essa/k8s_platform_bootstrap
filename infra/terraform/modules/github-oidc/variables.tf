variable "role_name" {
  description = "Name of the IAM role GitHub Actions assumes."
  type        = string
}

variable "subjects" {
  description = "Allowed OIDC subjects, exact match (e.g. repo:owner/name:ref:refs/heads/main or repo:owner/name:environment:prod)."
  type        = list(string)

  validation {
    condition     = length(var.subjects) > 0 && alltrue([for s in var.subjects : startswith(s, "repo:") && !strcontains(s, "*")])
    error_message = "Give at least one subject; each starts with repo: and has no wildcard."
  }
}

variable "policy_json" {
  description = "Inline IAM policy (JSON) with everything the role may do."
  type        = string
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
