resource "helm_release" "load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.6.2"
  atomic     = true
  wait       = true
  timeout    = 600
  values = [yamlencode({
    clusterName  = var.cluster_name
    region       = var.aws_region
    vpcId        = data.terraform_remote_state.cluster.outputs.vpc_id
    replicaCount = 1
    enableShield = false
    enableWaf    = false
    enableWafv2  = false
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
    }
    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { cpu = "500m", memory = "256Mi" }
    }
  })]
}
resource "kubernetes_ingress_v1" "api" {
  count = var.enable_public_ingress ? 1 : 0
  metadata {
    name      = "crewmeister-api"
    namespace = kubernetes_namespace_v1.crewmeister.metadata[0].name
    annotations = merge({
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/ip-address-type"  = "ipv4"
      "alb.ingress.kubernetes.io/subnets"          = join(",", data.terraform_remote_state.cluster.outputs.public_subnet_ids)
      "alb.ingress.kubernetes.io/inbound-cidrs"    = join(",", var.client_access_cidrs)
      "alb.ingress.kubernetes.io/healthcheck-path" = "/actuator/health/readiness"
      "alb.ingress.kubernetes.io/healthcheck-port" = "traffic-port"
      "alb.ingress.kubernetes.io/success-codes"    = "200"
      "alb.ingress.kubernetes.io/listen-ports"     = var.certificate_arn == null ? "[{\"HTTP\":80}]" : "[{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/tags"             = "Project=${var.cluster_name},Environment=aws-demo,ManagedBy=aws-load-balancer-controller"
      "alb.ingress.kubernetes.io/actions.reject"   = jsonencode({ type = "fixed-response", fixedResponseConfig = { contentType = "text/plain", statusCode = "404", messageBody = "Not found" } })
      }, var.certificate_arn == null ? {} : {
      "alb.ingress.kubernetes.io/certificate-arn" = var.certificate_arn
      "alb.ingress.kubernetes.io/ssl-policy"      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
    })
  }
  spec {
    ingress_class_name = "alb"
    default_backend {
      service {
        name = "reject"
        port {
          name = "use-annotation"
        }
      }
    }
    rule {
      http {
        path {
          path      = "/user"
          path_type = "Exact"
          backend {
            service {
              name = helm_release.application.name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
  wait_for_load_balancer = true
  depends_on             = [helm_release.load_balancer_controller, helm_release.application]
}
