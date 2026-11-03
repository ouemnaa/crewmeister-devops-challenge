data "aws_iam_policy_document" "cluster_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "cluster" {
  name               = "${var.cluster_name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_trust.json
}
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}
data "aws_iam_policy_document" "worker_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "worker" {
  name               = "${var.cluster_name}-worker"
  assume_role_policy = data.aws_iam_policy_document.worker_trust.json
}
resource "aws_iam_role_policy_attachment" "worker" {
  for_each   = toset(["AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryPullOnly"])
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}
resource "aws_iam_openid_connect_provider" "project" {
  url            = aws_eks_cluster.project.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
  # IAM retrieves the issuer CA thumbprint; no obsolete hardcoded thumbprint.
}
locals {
  oidc_host = replace(aws_iam_openid_connect_provider.project.url, "https://", "")
  service_accounts = {
    cni = "system:serviceaccount:kube-system:aws-node"
    ebs = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
    alb = "system:serviceaccount:kube-system:aws-load-balancer-controller"
  }
}
data "aws_iam_policy_document" "workload_trust" {
  for_each = local.service_accounts
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.project.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [each.value]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "workload" {
  for_each           = local.service_accounts
  name               = "${var.cluster_name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.workload_trust[each.key].json
}
resource "aws_iam_role_policy_attachment" "cni" {
  role       = aws_iam_role.workload["cni"].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "ebs" {
  role       = aws_iam_role.workload["ebs"].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
resource "aws_iam_policy" "alb" {
  name   = "${var.cluster_name}-alb"
  policy = file("${path.module}/policies/load-balancer-controller.json")
}
resource "aws_iam_role_policy_attachment" "alb" {
  role       = aws_iam_role.workload["alb"].name
  policy_arn = aws_iam_policy.alb.arn
}
