variable "name" {
  type = string
}

variable "backends" {
  description = "Backend key => the Lambda's live alias. Keys are referenced by route_backends."
  type = map(object({
    function_name = string
    alias_name    = string
    invoke_arn    = string
  }))
}

variable "route_backends" {
  description = "Route group => backend key. Change one entry to move a group to another implementation."
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

variable "jwt_audience" {
  type    = string
  default = "docbridge"
}

variable "cors_allowed_origins" {
  type = list(string)
}

variable "throttling_burst_limit" {
  type    = number
  default = 200
}

variable "throttling_rate_limit" {
  type    = number
  default = 100
}

variable "log_retention_days" {
  type    = number
  default = 30
}
