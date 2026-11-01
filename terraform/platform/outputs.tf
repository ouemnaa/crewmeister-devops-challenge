output "namespace" {
  description = "Namespace containing the project Helm releases and credentials."
  value       = kubernetes_namespace_v1.crewmeister.metadata[0].name
}

output "mysql_service" {
  description = "Cluster-internal MySQL service name."
  value       = helm_release.mysql.name
}

output "application_service" {
  description = "Cluster-internal service for application access and port forwarding."
  value       = helm_release.application.name
}
