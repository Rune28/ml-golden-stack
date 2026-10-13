# Same shape as the connection data of a managed ClickHouse. The password is
# a separate output, as for Postgres.

output "namespace" {
  value = kubernetes_namespace_v1.this.metadata[0].name
}

output "host" {
  value = "${kubernetes_service_v1.this.metadata[0].name}.${kubernetes_namespace_v1.this.metadata[0].name}.svc"

  # Clients (the migration job first) connect right away.
  depends_on = [kubernetes_stateful_set_v1.this]
}

output "http_port" {
  value = 8123
}

output "native_port" {
  value = 9000
}

output "user" {
  value = var.user
}

output "password" {
  value     = random_password.this.result
  sensitive = true
}
