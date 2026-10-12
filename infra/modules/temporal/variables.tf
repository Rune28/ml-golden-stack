variable "namespace" {
  type    = string
  default = "temporal"
}

variable "chart_version" {
  description = "Version of the temporalio/temporal chart. Chart 1.7.0 ships Temporal server 1.32.0 and UI 2.54.1."
  type        = string
  default     = "1.7.0"
}

variable "db" {
  description = "Postgres connection. In-cluster Postgres locally, a managed database (RDS, Cloud SQL) in the cloud."
  type = object({
    host = string
    port = number
    user = string
  })
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "num_history_shards" {
  description = <<-EOT
    Number of Temporal history shards. Cannot be changed after the first
    install without recreating the database. No default on purpose: every
    environment has to choose (small locally, 512 or more in production).
  EOT
  type        = number
}

variable "namespaces" {
  description = "Temporal namespaces created on install, with workflow history retention."
  type = list(object({
    name      = string
    retention = string
  }))
  default = [{ name = "default", retention = "3d" }]
}

variable "replicas" {
  description = "Replicas of each Temporal service and of the UI."
  type        = number
  default     = 1
}

variable "node_selector" {
  type    = map(string)
  default = {}
}

variable "web_service" {
  description = "Service of the UI, passed to the chart as `web.service`: ClusterIP, NodePort, LoadBalancer with annotations, ..."
  type        = any
  default     = { type = "ClusterIP" }
}
