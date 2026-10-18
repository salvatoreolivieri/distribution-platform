variable "name" {
  type = string
}

variable "service_clients" {
  type        = map(list(string))
  description = "Client id => scopes it may request."
  default = {
    "task-worker" = ["documents:ingest"]
  }
}
