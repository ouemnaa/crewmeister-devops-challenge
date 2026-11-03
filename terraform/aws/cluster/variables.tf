variable "aws_profile" {
  type        = string
  description = "Explicit temporary-credential profile; the unrelated default profile is forbidden."
  validation {
    condition     = length(trimspace(var.aws_profile)) > 0 && var.aws_profile != "default"
    error_message = "Supply a non-default AWS profile."
  }
}
variable "aws_region" {
  type    = string
  default = "eu-north-1"
  validation {
    condition     = var.aws_region == "eu-north-1"
    error_message = "This reviewed deployment targets Stockholm only."
  }
}
variable "expected_account_id" {
  type        = string
  description = "Private, independently supplied expected account ID."
  validation {
    condition     = can(regex("^[0-9]{12}$", var.expected_account_id))
    error_message = "Supply the expected 12-digit account ID."
  }
}
variable "cluster_name" {
  type    = string
  default = "crewmeister-aws"
  validation {
    condition     = can(regex("^crewmeister-aws(-[a-z0-9-]+)?$", var.cluster_name)) && length(var.cluster_name) <= 40
    error_message = "Use a crewmeister-aws name, at most 40 characters."
  }
}

variable "operator_role_arn" {
  type        = string
  description = "Durable IAM operator role to receive cluster access; never an STS session."
  validation {
    condition     = can(regex("^arn:aws:iam::${var.expected_account_id}:role/.+$", var.operator_role_arn))
    error_message = "Supply a role ARN in the expected account."
  }
}
variable "api_access_cidrs" {
  type        = list(string)
  description = "Approved administrator public IPv4 CIDRs; no world-open endpoint."
  validation {
    condition = length(var.api_access_cidrs) > 0 && alltrue([
      for cidr in var.api_access_cidrs : can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 24, false)
    ])
    error_message = "Supply explicit IPv4 CIDRs with prefix /24 or narrower; prefer /32."
  }
}
variable "instance_type" {
  type    = string
  default = "m7i-flex.large"
  validation {
    condition     = var.instance_type == "m7i-flex.large"
    error_message = "A different node requires a separate capacity/cost review."
  }
}
variable "vpc_cidr" {
  type    = string
  default = "10.42.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && try(tonumber(split("/", var.vpc_cidr)[1]) == 16, false)
    error_message = "Use a non-overlapping IPv4 /16."
  }
}
