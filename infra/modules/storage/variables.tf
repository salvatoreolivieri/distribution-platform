variable "name" {
  type = string
}

variable "cors_allowed_origins" {
  type        = list(string)
  description = "Web app origins allowed to upload to the staging bucket."
}

variable "upload_events_queue_arn" {
  type = string
}

variable "staging_safety_net_days" {
  type    = number
  default = 45
}

variable "force_destroy" {
  type    = bool
  default = false
}
