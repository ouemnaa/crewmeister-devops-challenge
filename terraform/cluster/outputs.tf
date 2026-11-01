output "cluster_name" {
  description = "Name of the project Kind cluster."
  value       = kind_cluster.crewmeister.name
}

output "context" {
  description = "Explicit Kubernetes context for project commands."
  value       = kind_cluster.crewmeister.context_name
}

output "kubeconfig_path" {
  description = "Dedicated project kubeconfig; contains cluster credentials."
  value       = kind_cluster.crewmeister.kubeconfig_path
}
