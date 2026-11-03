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
  description = "Private S3 backend bucket also containing the isolated AWS cluster state."
}
variable "image_repository" {
  type    = string
  default = "ghcr.io/ouemnaa/crewmeister-devops-challenge"
  validation {
    condition     = can(regex("^ghcr.io/[a-z0-9._/-]+$", var.image_repository))
    error_message = "Use a public GHCR repository."
  }
}
variable "image_tag" {
  type        = string
  description = "Full 40-character Git commit SHA already published to public GHCR."
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_tag))
    error_message = "Use an exact full commit SHA, never latest or a local tag."
  }
}
variable "client_access_cidrs" {
  type        = list(string)
  description = "Approved demonstration client IPv4 CIDRs."
  validation {
    condition = length(var.client_access_cidrs) > 0 && alltrue([
      for cidr in var.client_access_cidrs : can(cidrnetmask(cidr)) && try(tonumber(split("/", cidr)[1]) >= 24, false)
    ])
    error_message = "Supply IPv4 CIDRs /24 or narrower; prefer your /32."
  }
}
variable "enable_public_ingress" {
  type        = bool
  default     = false
  description = "Enable only after explicit approval of public API exposure."
}
variable "certificate_arn" {
  type        = string
  default     = null
  description = "Optional existing ACM certificate in Stockholm; no domain or certificate is created."
  validation {
    condition     = var.certificate_arn == null || can(regex("^arn:aws:acm:eu-north-1:${var.expected_account_id}:certificate/[a-f0-9-]+$", var.certificate_arn))
    error_message = "Use an existing Stockholm certificate in the expected account."
  }
}
