output "proxy_endpoint" {
  value = aws_db_proxy.this.endpoint
}

output "proxy_resource_id" {
  description = "Used in rds-db:connect ARNs for IAM authentication."
  value       = element(split(":", aws_db_proxy.this.arn), 6)
}

output "database_name" {
  value = var.database_name
}

output "instance_endpoint" {
  value = aws_db_instance.this.address
}

output "master_secret_arn" {
  description = "Secret RDS manages for the migrator user."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "role_secret_arns" {
  value = { for k, s in aws_secretsmanager_secret.role : k => s.arn }
}
