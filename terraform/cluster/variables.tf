variable "cgroup_v1_compatibility" {
  description = "Allow the documented Kubernetes 1.36 cgroup v1 fallback for older local Docker hosts. Prefer cgroup v2."
  type        = bool
  default     = false
}
