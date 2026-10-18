output "api_endpoint" {
  value = module.api.api_endpoint
}

output "websocket_url" {
  value = module.websocket.url
}

output "staging_bucket" {
  value = module.storage.staging_bucket
}

output "documents_bucket" {
  value = module.storage.documents_bucket
}

output "db_proxy_endpoint" {
  value = module.database.proxy_endpoint
}

output "db_instance_endpoint" {
  value = module.database.instance_endpoint
}

output "db_master_secret_arn" {
  value = module.database.master_secret_arn
}

output "db_role_secret_arns" {
  value = module.database.role_secret_arns
}
