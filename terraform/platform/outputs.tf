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

output "grafana_service" {
  description = "Internal Grafana service; use a localhost port forward for access."
  value       = "crewmeister-grafana"
}

output "prometheus_service" {
  description = "Internal Prometheus service for queries and target inspection."
  value       = "crewmeister-monitoring-prometheus"
}
