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

variable "state_bucket" {
  type        = string
  description = "Owner-selected globally unique bucket; keep its value in ignored private configuration."
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket))
    error_message = "Supply a valid S3 bucket name."
  }
}
variable "deployment_principal_arn" {
  type        = string
  description = "Durable IAM role ARN for state access, never an STS session ARN."
  validation {
    condition     = can(regex("^arn:aws:iam::${var.expected_account_id}:role/.+$", var.deployment_principal_arn))
    error_message = "Use an IAM role in the expected account."
  }
}
