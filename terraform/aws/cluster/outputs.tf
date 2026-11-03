output "cluster_name" {
  value = aws_eks_cluster.project.name
}
output "cluster_arn" {
  value = aws_eks_cluster.project.arn
}
output "vpc_id" {
  value = aws_vpc.project.id
}
output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}
output "alb_role_arn" {
  value = aws_iam_role.workload["alb"].arn
}
output "worker_security_group_id" {
  value = aws_security_group.worker.id
}
