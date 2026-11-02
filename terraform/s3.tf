data "aws_s3_bucket" "media" {
  bucket = var.media_bucket_name
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket = data.aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = data.aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = data.aws_s3_bucket.media.id

  versioning_configuration {
    status = "Enabled"
  }
}

output "s3_media_bucket_name" {
  description = "Nazwa bucketu na pliki multimedialne"
  value       = data.aws_s3_bucket.media.bucket
}

output "s3_media_bucket_arn" {
  description = "ARN bucketu S3 na pliki multimedialne"
  value       = data.aws_s3_bucket.media.arn
}
