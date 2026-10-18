variable "name" {
  type = string
}

variable "cidr_block" {
  type    = string
  default = "10.20.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "flow_log_retention_days" {
  type    = number
  default = 30
}

variable "single_nat_gateway" {
  type        = bool
  description = "One NAT gateway for all AZs (cheaper, not AZ-resilient). true in dev."
  default     = true
}
