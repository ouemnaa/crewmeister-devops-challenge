resource "kubernetes_storage_class_v1" "mysql" {
  metadata {
    name = "crewmeister-gp3"
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type                        = "gp3"
    encrypted                   = "true"
    "csi.storage.k8s.io/fstype" = "ext4"
    tagSpecification_1          = "Project=${var.cluster_name}"
    tagSpecification_2          = "Environment=aws-demo"
  }
}
