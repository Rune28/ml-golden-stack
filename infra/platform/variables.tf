variable "cluster_state_path" {
  description = "State file of the cluster layer (`infra/local`)."
  type        = string
  default     = "../local/terraform.tfstate"
}

variable "platform_node_selector" {
  description = "Node selector for platform services. They stay off the gpu-sim pool, which is reserved for model steps."
  type        = map(string)
  default     = { "node-pool" = "cpu" }
}

variable "temporal_chart_version" {
  description = "Version of the temporalio/temporal chart. Chart 1.7.0 ships Temporal server 1.32.0 and UI 2.54.1."
  type        = string
  default     = "1.7.0"
}

variable "temporal_num_history_shards" {
  description = <<-EOT
    Number of Temporal history shards. Cannot be changed after the first
    install without recreating the database. Small locally to keep the
    footprint low; a production cluster uses 512 or more.
  EOT
  type        = number
  default     = 4
}

variable "temporal_namespaces" {
  description = "Temporal namespaces created on install, with workflow history retention."
  type = list(object({
    name      = string
    retention = string
  }))
  default = [{ name = "default", retention = "3d" }]
}

variable "temporal_ui_node_port" {
  description = "NodePort of the Temporal UI. Must match `port_mappings.temporal-ui.node_port` in `infra/local`."
  type        = number
  default     = 30080
}

variable "postgres_image" {
  description = "Postgres image for Temporal persistence. Local only: on EKS Temporal uses RDS."
  type        = string
  default     = "postgres:17.11-alpine"
}

variable "postgres_storage_size" {
  description = "Size of the Postgres volume."
  type        = string
  default     = "2Gi"
}
