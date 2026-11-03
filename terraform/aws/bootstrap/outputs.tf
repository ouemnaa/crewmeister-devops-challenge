output "state_bucket" {
  value = aws_s3_bucket.state.id
}
output "state_access_policy_arn" {
  description = "Scoped state policy; attachment to an operator role is a separately reviewed IAM decision."
  value       = aws_iam_policy.state_access.arn
}
