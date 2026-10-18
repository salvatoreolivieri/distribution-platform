# Two private buckets, each with its own customer-managed KMS key:
# - staging: the browser uploads here with presigned POST (or multipart), and object-created
#   events go to the upload-events queue. Owned by DocBridge.
# - documents: the platform copies bytes here at ingest. Owned by the platform; no CORS.

# ---- keys

resource "aws_kms_key" "staging" {
  description         = "${var.name} staging bucket"
  enable_key_rotation = true
}

resource "aws_kms_alias" "staging" {
  name          = "alias/${var.name}-staging"
  target_key_id = aws_kms_key.staging.key_id
}

resource "aws_kms_key" "documents" {
  description         = "${var.name} documents bucket"
  enable_key_rotation = true
}

resource "aws_kms_alias" "documents" {
  name          = "alias/${var.name}-documents"
  target_key_id = aws_kms_key.documents.key_id
}

# ---- staging bucket

resource "aws_s3_bucket" "staging" {
  bucket        = "${var.name}-staging"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "staging" {
  bucket                  = aws_s3_bucket.staging.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "staging" {
  bucket = aws_s3_bucket.staging.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "staging" {
  bucket = aws_s3_bucket.staging.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.staging.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_cors_configuration" "staging" {
  bucket = aws_s3_bucket.staging.id
  cors_rule {
    allowed_methods = ["POST", "PUT"]
    allowed_origins = var.cors_allowed_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag", "x-amz-checksum-sha256", "x-amz-checksum-type", "x-amz-version-id"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "staging" {
  bucket = aws_s3_bucket.staging.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  # Safety net only. The real 30-day purge is a job driven by jobs.completed_at; this catches
  # anything it misses.
  rule {
    id     = "staging-safety-net"
    status = "Enabled"
    filter {
      prefix = "staging/"
    }
    expiration {
      days = var.staging_safety_net_days
    }
  }
}

resource "aws_s3_bucket_policy" "staging" {
  bucket = aws_s3_bucket.staging.id
  policy = data.aws_iam_policy_document.tls_only["staging"].json
}

resource "aws_s3_bucket_notification" "staging" {
  bucket = aws_s3_bucket.staging.id
  queue {
    queue_arn     = var.upload_events_queue_arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "staging/"
  }
}

# ---- documents bucket

resource "aws_s3_bucket" "documents" {
  bucket        = "${var.name}-documents"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket                  = aws_s3_bucket.documents.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.documents.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_policy" "documents" {
  bucket = aws_s3_bucket.documents.id
  policy = data.aws_iam_policy_document.tls_only["documents"].json
}

data "aws_iam_policy_document" "tls_only" {
  for_each = {
    staging   = aws_s3_bucket.staging.arn
    documents = aws_s3_bucket.documents.arn
  }
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value, "${each.value}/*"]
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
}
