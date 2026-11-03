output "api_hostname" {
  value = try(kubernetes_ingress_v1.api[0].status[0].load_balancer[0].ingress[0].hostname, null)
}
output "namespace" {
  value = kubernetes_namespace_v1.crewmeister.metadata[0].name
}
