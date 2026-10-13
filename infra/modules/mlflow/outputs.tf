output "tracking_uri" {
  description = "MLflow URL for clients inside the cluster: tracking, registry and artifacts."
  value       = "http://${local.host}:${local.port}"

  depends_on = [kubernetes_deployment_v1.this]
}
