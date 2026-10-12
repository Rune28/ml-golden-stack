variable "cluster_state_path" {
  description = "State file of the cluster layer."
  type        = string
  default     = "../../clusters/kind/terraform.tfstate"
}

variable "temporal_ui_node_port" {
  description = "NodePort of the Temporal UI. Must match `port_mappings.temporal-ui.node_port` of the kind cluster."
  type        = number
  default     = 30080
}
