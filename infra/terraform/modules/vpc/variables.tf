variable "name" {
  description = "Name prefix for every resource (Name tags)."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR. Needs to be a /16 (or larger) for the /19 private subnets."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr, 0)) && tonumber(split("/", var.cidr)[1]) <= 16
    error_message = "cidr must be a valid IPv4 CIDR of /16 or larger."
  }
}

variable "azs" {
  description = "Availability zones, one public and one private subnet in each (2 to 8)."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 8
    error_message = "Give between 2 and 8 availability zones."
  }
}

variable "single_nat_gateway" {
  description = "One NAT gateway for the VPC (cheap, one AZ is a dependency) or one per AZ."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
