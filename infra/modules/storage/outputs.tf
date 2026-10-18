output "staging_bucket" {
  value = aws_s3_bucket.staging.id
}

output "staging_bucket_arn" {
  value = aws_s3_bucket.staging.arn
}

output "staging_kms_key_arn" {
  value = aws_kms_key.staging.arn
}

output "documents_bucket" {
  value = aws_s3_bucket.documents.id
}

output "documents_bucket_arn" {
  value = aws_s3_bucket.documents.arn
}

output "documents_kms_key_arn" {
  value = aws_kms_key.documents.arn
}
