resource "random_password" "grafana" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "grafana" {
  metadata {
    name      = "crewmeister-grafana-admin"
    namespace = kubernetes_namespace_v1.crewmeister.metadata[0].name
  }
  data = {
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana.result
  }
}

resource "helm_release" "monitoring" {
  name       = "crewmeister-monitoring"
  namespace  = kubernetes_namespace_v1.crewmeister.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "92.17.0"
  atomic     = true
  wait       = true
  timeout    = 1200

  values = [
    file("${path.module}/../../../monitoring/values.yaml"),
    file("${path.module}/monitoring-values.yaml"),
    yamlencode({
      grafana = {
        admin = {
          existingSecret = kubernetes_secret_v1.grafana.metadata[0].name
        }
        dashboards = {
          crewmeister = {
            crewmeister = {
              json = file("${path.module}/../../../monitoring/dashboards/crewmeister.json")
            }
          }
        }
      }
    })
  ]
}

resource "helm_release" "mysql_exporter" {
  name       = "crewmeister-mysql-exporter"
  namespace  = kubernetes_namespace_v1.crewmeister.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus-mysql-exporter"
  version    = "2.16.0"
  atomic     = true
  wait       = true
  timeout    = 600

  values = [
    file("${path.module}/../../../monitoring/mysql-exporter.yaml"),
    yamlencode({
      mysql = {
        host = "crewmeister-mysql"
        user = "crewmeister"
        existingPasswordSecret = {
          name = kubernetes_secret_v1.database.metadata[0].name
          key  = "password"
        }
      }
    })
  ]
  depends_on = [helm_release.mysql, helm_release.monitoring]
}
