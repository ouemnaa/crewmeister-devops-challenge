data "aws_availability_zones" "available" {
  state = "available"
}
resource "aws_vpc" "project" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name          = var.cluster_name
    TerraformRoot = "aws/cluster"
  }
}
resource "aws_internet_gateway" "project" {
  vpc_id = aws_vpc.project.id
  tags   = { Name = var.cluster_name }
}
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.project.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name                                        = "${var.cluster_name}-public-${count.index + 1}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.project.id
  tags   = { Name = var.cluster_name }
}
resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.project.id
}
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_security_group" "control_plane" {
  name_prefix = "${var.cluster_name}-api-"
  description = "Project control plane; EKS also manages its cluster security group."
  vpc_id      = aws_vpc.project.id
  tags        = { Name = "${var.cluster_name}-api" }
}
resource "aws_security_group" "worker" {
  name_prefix = "${var.cluster_name}-node-"
  description = "One demo node; no SSH or public NodePort ingress."
  vpc_id      = aws_vpc.project.id
  tags        = { Name = "${var.cluster_name}-node" }
}
resource "aws_vpc_security_group_egress_rule" "worker" {
  security_group_id = aws_security_group.worker.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
resource "aws_vpc_security_group_ingress_rule" "worker_self" {
  security_group_id            = aws_security_group.worker.id
  referenced_security_group_id = aws_security_group.worker.id
  ip_protocol                  = "-1"
}
resource "aws_vpc_security_group_ingress_rule" "worker_control_plane" {
  security_group_id            = aws_security_group.worker.id
  referenced_security_group_id = aws_eks_cluster.project.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 1025
  to_port                      = 65535
}
resource "aws_vpc_security_group_ingress_rule" "api_worker" {
  security_group_id            = aws_eks_cluster.project.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = aws_security_group.worker.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}
