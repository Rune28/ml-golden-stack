variable "cluster_state_path" {
  description = "State file of the cluster layer."
  type        = string
  default     = "../../clusters/kind/terraform.tfstate"
}

variable "images" {
  description = <<-EOT
    Images of the applications, repository:tag. `make platform-up` writes
    images.auto.tfvars.json with tags derived from the image content, so a
    changed image rolls the pods and an unchanged one changes nothing.
  EOT
  type = object({
    be_service = string
    de_worker  = string
    mle_models = string
  })
  default = {
    be_service = "ghcr.io/rune28/be-service:latest"
    de_worker  = "ghcr.io/rune28/de-worker:latest"
    mle_models = "ghcr.io/rune28/mle-models:latest"
  }
}

variable "app_node_port" {
  description = "NodePort of the pipeline page. Must match `port_mappings.app.node_port` of the kind cluster."
  type        = number
  default     = 30901
}

variable "mlflow_ui_node_port" {
  description = "NodePort of the MLflow UI. Must match `port_mappings.mlflow.node_port` of the kind cluster."
  type        = number
  default     = 30500
}

variable "temporal_ui_node_port" {
  description = "NodePort of the Temporal UI. Must match `port_mappings.temporal-ui.node_port` of the kind cluster."
  type        = number
  default     = 30080
}
