# Same shape as the connection data of a managed database, so clients do not
# care which one they get. The password is a separate output: a sensitive
# host would hide the whole helm values diff of every client in `plan`.

output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "host" {
  value = "${kubernetes_service_v1.this.metadata[0].name}.${kubernetes_namespace_v1.this.metadata[0].name}.svc"

  # Clients connect right away (Temporal's schema job), so the database
  # must be running, not only declared.
  depends_on = [kubernetes_stateful_set_v1.this]
}

output "port" {
  value = 5432
}

output "user" {
  value = var.user
}

output "password" {
  value     = random_password.this.result
  sensitive = true
}
