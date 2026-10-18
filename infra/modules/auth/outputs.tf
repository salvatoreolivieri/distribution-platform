output "jwt_key_arn" {
  value = aws_kms_key.jwt.arn
}

output "jwt_key_alias" {
  value = aws_kms_alias.jwt.name
}

output "client_secret_arns" {
  value = { for k, s in aws_secretsmanager_secret.client : k => s.arn }
}
