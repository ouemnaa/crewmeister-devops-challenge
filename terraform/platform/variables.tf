variable "kubeconfig_path" {
  description = "Dedicated project kubeconfig, relative to terraform/platform or absolute."
  type        = string
  default     = "../../.local/crewmeister.kubeconfig"
}

variable "image_repository" {
  description = "Application image repository, such as a public GHCR repository or a locally loaded image."
  type        = string
  default     = "crewmeister-app"
}

variable "image_tag" {
  description = "Immutable application image tag or an explicit local development tag."
  type        = string
  default     = "local"

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image_tag))
    error_message = "Use a valid, nonempty Docker image tag."
  }
}

variable "image_pull_policy" {
  description = "Never for images loaded into Kind, or IfNotPresent/Always for registry images."
  type        = string
  default     = "Never"

  validation {
    condition     = contains(["Never", "IfNotPresent", "Always"], var.image_pull_policy)
    error_message = "Use Never, IfNotPresent, or Always."
  }
}

variable "kube_context" {
  description = "Explicit Kubernetes context for the local project cluster."
  type        = string
  default     = "kind-crewmeister"

  validation {
    condition     = var.kube_context == "kind-crewmeister"
    error_message = "The local platform must target kind-crewmeister."
  }
}
