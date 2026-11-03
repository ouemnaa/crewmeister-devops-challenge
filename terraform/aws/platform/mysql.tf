resource "random_password" "mysql_root" {
  length  = 32
  special = false
}

resource "random_password" "database" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "mysql_root" {
  metadata {
    name      = "crewmeister-mysql-root"
    namespace = kubernetes_namespace_v1.crewmeister.metadata[0].name
  }

  data = {
    password = random_password.mysql_root.result
  }
}

resource "kubernetes_secret_v1" "database" {
  metadata {
    name      = "crewmeister-database"
    namespace = kubernetes_namespace_v1.crewmeister.metadata[0].name
  }

  data = {
    database = "challenge"
    username = "crewmeister"
    password = random_password.database.result
  }
}

resource "helm_release" "mysql" {
  name       = "crewmeister-mysql"
  namespace  = kubernetes_namespace_v1.crewmeister.metadata[0].name
  repository = "https://groundhog2k.github.io/helm-charts/"
  chart      = "mysql"
  version    = "3.1.5"
  atomic     = true
  wait       = true
  timeout    = 600

  depends_on = [kubernetes_storage_class_v1.mysql]

  values = [
    file("${path.module}/../../platform/mysql-values.yaml"),
    file("${path.module}/mysql-values.yaml"),
    yamlencode({
      settings = {
        existingSecret = kubernetes_secret_v1.mysql_root.metadata[0].name
      }
      userDatabase = {
        existingSecret = kubernetes_secret_v1.database.metadata[0].name
      }
    })
  ]
}
