variable "environment" {
  type = string
}

variable "region" {
  type    = string
  default = "eu-west-1"
}

variable "platform_region" {
  type        = string
  description = "Platform region served by this deployment (eu or us)."
  default     = "eu"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "single_nat_gateway" {
  type    = bool
  default = true
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_multi_az" {
  type    = bool
  default = false
}

variable "db_deletion_protection" {
  type    = bool
  default = false
}

variable "retry_budget" {
  type    = number
  default = 5
}

variable "jwt_audience" {
  type    = string
  default = "docbridge"
}

variable "web_origins" {
  type        = list(string)
  description = "Origins of the web app (CORS on the API and the staging bucket)."
}

variable "log_level" {
  type    = string
  default = "info"
}

variable "route_backends" {
  description = "Route group => backend (auth, platform, api). See modules/api."
  type        = map(string)
  default = {
    auth         = "auth"
    auth_me      = "auth"
    browse       = "platform"
    documents    = "platform"
    ingest       = "platform"
    destinations = "api"
    jobs         = "api"
    files        = "api"
  }
}
