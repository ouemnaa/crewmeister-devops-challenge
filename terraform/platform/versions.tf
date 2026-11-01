terraform {
  required_version = "= 1.15.8"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "3.3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }
}

provider "kubernetes" {
  config_path    = abspath(var.kubeconfig_path)
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = abspath(var.kubeconfig_path)
    config_context = var.kube_context
  }
}
