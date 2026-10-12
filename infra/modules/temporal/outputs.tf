output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "frontend_address" {
  description = "gRPC address of the Temporal frontend for workers inside the cluster."
  value       = "temporal-frontend.${kubernetes_namespace_v1.this.metadata[0].name}.svc:7233"
}
