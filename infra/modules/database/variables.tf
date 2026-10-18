variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "client_security_group_ids" {
  type        = list(string)
  description = "Security groups allowed to reach the proxy (the Lambdas)."
}

variable "service_roles" {
  type    = list(string)
  default = ["auth_svc", "platform_svc", "docbridge_svc", "worker_svc"]
}

variable "database_name" {
  type    = string
  default = "docbridge"
}

variable "engine_version" {
  type    = string
  default = "17.6"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  type    = bool
  default = false
}
