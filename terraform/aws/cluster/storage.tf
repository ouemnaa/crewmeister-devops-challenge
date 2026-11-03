resource "aws_eks_addon" "ebs" {
  cluster_name                = aws_eks_cluster.project.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = "v1.67.2-eksbuild.1"
  service_account_role_arn    = aws_iam_role.workload["ebs"].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_node_group.worker, aws_iam_role_policy_attachment.ebs]
}
