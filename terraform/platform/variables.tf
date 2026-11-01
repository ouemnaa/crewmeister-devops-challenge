variable "kubeconfig_path" {
  description = "Dedicated project kubeconfig, relative to terraform/platform or absolute."
  type        = string
  default     = "../../.local/crewmeister.kubeconfig"
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
