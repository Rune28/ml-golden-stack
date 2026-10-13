output "job_name" {
  description = "Completed migration job. Applications depend on this module, so they start on the current schema."
  value       = kubernetes_job_v1.this.metadata[0].name
}
