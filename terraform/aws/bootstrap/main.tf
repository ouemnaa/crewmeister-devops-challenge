resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}
resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
locals {
  state_objects = [
    "${aws_s3_bucket.state.arn}/crewmeister/aws/cluster.tfstate",
    "${aws_s3_bucket.state.arn}/crewmeister/aws/platform.tfstate"
  ]
  lock_objects = [for key in local.state_objects : "${key}.tflock"]
}
data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "RequireTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
  statement {
    sid       = "RestrictPrincipals"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "ArnNotEquals"
      variable = "aws:PrincipalArn"
      values   = [var.deployment_principal_arn, "arn:aws:iam::${var.expected_account_id}:root"]
    }
  }
  # Policy removal needs a separately reviewed recovery/cleanup procedure.
  statement {
    sid       = "ProtectBucketAndStateVersions"
    effect    = "Deny"
    actions   = ["s3:DeleteBucket", "s3:DeleteObjectVersion"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
  statement {
    sid       = "ProtectCurrentStates"
    effect    = "Deny"
    actions   = ["s3:DeleteObject"]
    resources = local.state_objects
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}
resource "aws_s3_bucket_policy" "state" {
  bucket     = aws_s3_bucket.state.id
  policy     = data.aws_iam_policy_document.bucket.json
  depends_on = [aws_s3_bucket_public_access_block.state]
}
data "aws_iam_policy_document" "state_access" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = local.state_objects
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = local.lock_objects
  }
}
resource "aws_iam_policy" "state_access" {
  name   = "${var.cluster_name}-state-access"
  policy = data.aws_iam_policy_document.state_access.json
}
