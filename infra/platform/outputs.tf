output "temporal_ui_url" {
  value = local.cluster.service_urls["temporal-ui"]
}

output "temporal_frontend_address" {
  description = "gRPC address of the Temporal frontend for workers inside the cluster."
  value       = "temporal-frontend.${kubernetes_namespace_v1.temporal.metadata[0].name}.svc:7233"
}
