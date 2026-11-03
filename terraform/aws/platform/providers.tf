provider "aws" {
  profile             = var.aws_profile
  region              = var.aws_region
  allowed_account_ids = [var.expected_account_id]
  default_tags {
    tags = {
      Project     = var.cluster_name
      Environment = "aws-demo"
      ManagedBy   = "Terraform"
    }
  }
}

data "terraform_remote_state" "cluster" {
  backend = "s3"
  config = {
    bucket              = var.state_bucket
    key                 = "crewmeister/aws/cluster.tfstate"
    region              = var.aws_region
    profile             = var.aws_profile
    allowed_account_ids = [var.expected_account_id]
    encrypt             = true
    use_lockfile        = true
  }
}
data "aws_eks_cluster" "project" {
  name = var.cluster_name
  lifecycle {
    postcondition {
      condition = (
        self.arn == "arn:aws:eks:${var.aws_region}:${var.expected_account_id}:cluster/${var.cluster_name}" &&
        self.arn == data.terraform_remote_state.cluster.outputs.cluster_arn &&
        self.vpc_config[0].vpc_id == data.terraform_remote_state.cluster.outputs.vpc_id &&
        try(self.tags["Project"], "") == var.cluster_name &&
        self.status == "ACTIVE"
      )
      error_message = "The cluster, account, ownership tags or remote AWS state do not match."
    }
  }
}
provider "kubernetes" {
  host                   = data.aws_eks_cluster.project.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.project.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--profile", var.aws_profile, "--region", var.aws_region]
  }
}
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.project.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.project.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--profile", var.aws_profile, "--region", var.aws_region]
    }
  }
}
