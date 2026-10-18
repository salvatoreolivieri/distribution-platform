variable "name" {
  type = string
}

variable "staging_bucket_arn" {
  type        = string
  description = "Only this bucket may send to upload-events."
}

variable "retry_budget" {
  type        = number
  description = "Receives of a task message before it moves to tasks-dlq."
  default     = 5
}

variable "worker_timeout" {
  type    = number
  default = 60
}

variable "upload_handler_timeout" {
  type    = number
  default = 30
}

variable "worker_max_concurrency" {
  type    = number
  default = 10
}

variable "watchdog_schedule" {
  type    = string
  default = "rate(5 minutes)"
}

variable "upload_handler_arn" {
  type = string
}

variable "worker_arn" {
  type = string
}

variable "dlq_handler_arn" {
  type = string
}

variable "watchdog_arn" {
  type = string
}
