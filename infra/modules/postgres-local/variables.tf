variable "namespace" {
  description = "Namespace for the database, separate from its clients."
  type        = string
  default     = "postgres"
}

variable "name" {
  description = "Name of the StatefulSet, Service and Secret."
  type        = string
  default     = "postgres"
}

variable "user" {
  description = "Superuser name."
  type        = string
  default     = "postgres"
}

variable "image" {
  type    = string
  default = "postgres:17.11-alpine"
}

variable "storage_size" {
  type    = string
  default = "2Gi"
}

variable "node_selector" {
  type    = map(string)
  default = {}
}
