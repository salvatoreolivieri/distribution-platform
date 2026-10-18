variable "name" {
  type = string
}

variable "stage_name" {
  type    = string
  default = "live"
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "ws_function_name" {
  type = string
}

variable "ws_alias_name" {
  type = string
}

variable "ws_invoke_arn" {
  type = string
}
