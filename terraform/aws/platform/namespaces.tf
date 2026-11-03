resource "kubernetes_namespace_v1" "crewmeister" {
  metadata {
    name = "crewmeister"
    labels = {
      "app.kubernetes.io/part-of" = var.cluster_name
    }
  }
}
