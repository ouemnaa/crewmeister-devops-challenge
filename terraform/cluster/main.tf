resource "kind_cluster" "crewmeister" {
  name            = "crewmeister"
  node_image      = "kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"
  wait_for_ready  = true
  kubeconfig_path = abspath("${path.module}/../../.local/crewmeister.kubeconfig")

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    networking {
      api_server_address = "127.0.0.1"
      api_server_port    = 0
    }

    node {
      role = "control-plane"

      kubeadm_config_patches = var.cgroup_v1_compatibility ? [yamlencode({
        apiVersion   = "kubelet.config.k8s.io/v1beta1"
        kind         = "KubeletConfiguration"
        failCgroupV1 = false
      })] : []
    }
  }
}
