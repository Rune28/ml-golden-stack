# Connection data for the client, in the same shape as postgres-local's.

output "host" {
  value = var.postgres.host

  # The database exists once the job has completed.
  depends_on = [kubernetes_job_v1.this]
}

output "port" {
  value = var.postgres.port
}

output "database" {
  value = var.name
}

output "user" {
  value = var.name
}

output "password" {
  value     = random_password.this.result
  sensitive = true
}
