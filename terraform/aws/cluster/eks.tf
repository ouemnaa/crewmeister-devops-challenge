resource "aws_eks_cluster" "project" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = "1.36"
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  upgrade_policy {
    support_type = "STANDARD"
  }
  vpc_config {
    subnet_ids              = aws_subnet.public[*].id
    security_group_ids      = [aws_security_group.control_plane.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.api_access_cidrs
  }
  tags       = { TerraformRoot = "aws/cluster" }
  depends_on = [aws_iam_role_policy_attachment.cluster, aws_route_table_association.public, aws_route.internet]
}
resource "aws_eks_access_entry" "operator" {
  cluster_name  = aws_eks_cluster.project.name
  principal_arn = var.operator_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "operator" {
  cluster_name  = aws_eks_cluster.project.name
  principal_arn = aws_eks_access_entry.operator.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
resource "aws_launch_template" "worker" {
  name_prefix            = "${var.cluster_name}-"
  vpc_security_group_ids = [aws_security_group.worker.id]
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 30
      encrypted             = true
      delete_on_termination = true
    }
  }
  tag_specifications {
    resource_type = "instance"
    tags = {
      Project       = var.cluster_name
      Environment   = "aws-demo"
      ManagedBy     = "Terraform"
      TerraformRoot = "aws/cluster"
    }
  }
  tag_specifications {
    resource_type = "volume"
    tags = {
      Project     = var.cluster_name
      Environment = "aws-demo"
      ManagedBy   = "Terraform"
    }
  }
}
resource "aws_eks_node_group" "worker" {
  cluster_name    = aws_eks_cluster.project.name
  node_group_name = "${var.cluster_name}-demo"
  node_role_arn   = aws_iam_role.worker.arn
  # Keep the only node in one AZ so replacement nodes can reattach its EBS PVC.
  subnet_ids     = [aws_subnet.public[0].id]
  instance_types = [var.instance_type]
  capacity_type  = "ON_DEMAND"
  ami_type       = "AL2023_x86_64_STANDARD"
  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }
  launch_template {
    id      = aws_launch_template.worker.id
    version = aws_launch_template.worker.latest_version
  }
  update_config {
    max_unavailable = 1
  }
  depends_on = [
    aws_iam_role_policy_attachment.worker,
    aws_eks_addon.vpc_cni,
    aws_vpc_security_group_ingress_rule.worker_self,
    aws_vpc_security_group_ingress_rule.worker_control_plane,
    aws_vpc_security_group_ingress_rule.api_worker
  ]
}
resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.project.name
  addon_name    = "vpc-cni"
  addon_version = "v1.22.4-eksbuild.10"
  pod_identity_association {
    role_arn        = aws_iam_role.workload["cni"].arn
    service_account = local.service_accounts.cni
  }
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_addon.pod_identity, aws_iam_role_policy_attachment.cni]
}
resource "aws_eks_addon" "pod_identity" {
  cluster_name                = aws_eks_cluster.project.name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = "v1.4.1-eksbuild.3"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_iam_role_policy_attachment.worker]
}
resource "aws_eks_addon" "core" {
  for_each = {
    coredns    = "v1.14.7-eksbuild.22"
    kube-proxy = "v1.36.0-eksbuild.58"
  }
  cluster_name                = aws_eks_cluster.project.name
  addon_name                  = each.key
  addon_version               = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_node_group.worker]
}
