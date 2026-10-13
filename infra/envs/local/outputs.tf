output "temporal_ui_url" {
  value = local.cluster.service_urls["temporal-ui"]
}

output "temporal_frontend_address" {
  value = module.temporal.frontend_address
}

output "mlflow_ui_url" {
  value = local.cluster.service_urls["mlflow"]
}

output "mlflow_tracking_uri" {
  description = "For clients inside the cluster."
  value       = module.mlflow.tracking_uri
}

output "app_url" {
  description = "The pipeline page."
  value       = local.cluster.service_urls["app"]
}
