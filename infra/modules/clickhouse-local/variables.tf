variable "namespace" {
  description = "Namespace for the database, separate from its clients."
  type        = string
  default     = "clickhouse"
}

variable "name" {
  description = "Name of the StatefulSet, Service, ConfigMap and Secret."
  type        = string
  default     = "clickhouse"
}

variable "user" {
  description = "Admin user, like the default user of a managed ClickHouse. Databases and tables come from migrations."
  type        = string
  default     = "platform"
}

variable "image" {
  description = "26.8 is an LTS release."
  type        = string
  default     = "clickhouse/clickhouse-server:26.8.25.14"
}

variable "storage_size" {
  type    = string
  default = "5Gi"
}

variable "node_selector" {
  type    = map(string)
  default = {}
}
