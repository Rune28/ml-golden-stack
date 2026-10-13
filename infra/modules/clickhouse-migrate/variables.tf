variable "namespace" {
  description = "Namespace the migration job runs in."
  type        = string
}

variable "name" {
  description = "Prefix of the job, ConfigMap and Secret."
  type        = string
  default     = "clickhouse-migrate"
}

variable "migrations_dir" {
  description = "Directory with golang-migrate files: <version>_<name>.up.sql / .down.sql, one statement per file."
  type        = string
}

variable "clickhouse" {
  description = "Connection over the native protocol."
  type = object({
    host        = string
    native_port = number
    user        = string
  })
}

variable "clickhouse_password" {
  type      = string
  sensitive = true
}

variable "image" {
  type    = string
  default = "migrate/migrate:v4.20.1"
}

variable "node_selector" {
  type    = map(string)
  default = {}
}
