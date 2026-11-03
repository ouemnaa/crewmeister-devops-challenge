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
locals {
  service_accounts = {
    cni = "aws-node"
    ebs = "ebs-csi-controller-sa"
    alb = "aws-load-balancer-controller"
  }
}
data "aws_iam_policy_document" "workload_trust" {
  for_each = local.service_accounts
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-service-account"
      values   = [each.value]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes-namespace"
      values   = ["kube-system"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/eks-cluster-arn"
      # This ARN is stable across endpoint updates; keep trust policies known
      # during planning rather than rewriting all roles when the API IP changes.
      values = ["arn:aws:eks:${var.aws_region}:${var.expected_account_id}:cluster/${var.cluster_name}"]
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
  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}
resource "aws_eks_pod_identity_association" "alb" {
  cluster_name    = aws_eks_cluster.project.name
  namespace       = "kube-system"
  service_account = local.service_accounts.alb
  role_arn        = aws_iam_role.workload["alb"].arn
  depends_on      = [aws_eks_addon.pod_identity, aws_iam_role_policy_attachment.alb]
}
resource "aws_iam_policy" "alb" {
  name   = "${var.cluster_name}-alb"
  policy = file("${path.module}/policies/load-balancer-controller.json")
}
resource "aws_iam_role_policy_attachment" "alb" {
  role       = aws_iam_role.workload["alb"].name
  policy_arn = aws_iam_policy.alb.arn
}
