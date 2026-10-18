variable "name" {
  type = string
}

variable "runtime_kind" {
  type        = string
  description = "go, python or java."
  validation {
    condition     = contains(["go", "python", "java"], var.runtime_kind)
    error_message = "runtime_kind must be go, python or java."
  }
}

variable "handler" {
  type        = string
  description = "Handler for python and java (ignored for go, which uses bootstrap)."
  default     = null
}

variable "artifact_path" {
  type        = string
  description = "Zip produced by `just build` (dist/<name>.zip)."
}

variable "snapstart" {
  type        = bool
  description = "SnapStart on published versions. Python and Java only."
  default     = false
}

variable "memory_size" {
  type    = number
  default = 256
}

variable "timeout" {
  type    = number
  default = 15
}

variable "reserved_concurrency" {
  type    = number
  default = -1
}

variable "environment" {
  type    = map(string)
  default = {}
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "policy_json" {
  type        = string
  description = "Extra IAM policy for what this function does (S3, SQS, KMS, ...)."
  default     = null
}

variable "log_retention_days" {
  type    = number
  default = 30
}
