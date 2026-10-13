# Same shape as the connection data of S3 / GCS (HMAC keys), so clients do
# not care which one they get. The secret key is a separate sensitive output,
# as the Postgres password is.

output "endpoint" {
  value = "http://${local.host}:${local.ports.s3}"

  # Clients use the buckets right away.
  depends_on = [kubernetes_job_v1.buckets]
}

output "access_key" {
  value = local.access_key
}

output "secret_key" {
  value     = random_password.secret_key.result
  sensitive = true
}

output "buckets" {
  value = var.buckets
}
