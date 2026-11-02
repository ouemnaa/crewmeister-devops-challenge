locals {
  application_chart = "${path.module}/../../helm/crewmeister-app"
  application_chart_checksum = sha256(join("", [
    for file in sort(tolist(fileset(local.application_chart, "**"))) :
    filesha256("${local.application_chart}/${file}")
  ]))
}

resource "helm_release" "application" {
  name      = "crewmeister-app"
  namespace = kubernetes_namespace_v1.crewmeister.metadata[0].name
  chart     = local.application_chart
  atomic    = true
  wait      = true
  timeout   = 600

  values = [
    file("${local.application_chart}/values-local.yaml"),
    yamlencode({
      image = {
        repository = var.image_repository
        tag        = var.image_tag
        pullPolicy = var.image_pull_policy
      }
      database = {
        host           = helm_release.mysql.name
        existingSecret = kubernetes_secret_v1.database.metadata[0].name
      }
      podAnnotations = {
        "checksum/chart" = local.application_chart_checksum
      }
      serviceMonitor = {
        enabled = true
        release = helm_release.monitoring.name
      }
    })
  ]

  depends_on = [helm_release.mysql, helm_release.monitoring]
}
