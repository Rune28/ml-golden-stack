# Applies ClickHouse migrations as a one-off Job before applications start.
# The SQL files come from the repository through a ConfigMap, so the stock
# migrate image is enough and migrations ship with the same commit as the
# infrastructure.

locals {
  files = {
    for f in fileset(var.migrations_dir, "*.sql") : f => file("${var.migrations_dir}/${f}")
  }

  # The job name follows the migrations: no new files, same name, nothing
  # runs again; a new file gives a new name and a new job.
  migrations_hash = substr(sha256(jsonencode(local.files)), 0, 8)
}

resource "kubernetes_config_map_v1" "migrations" {
  metadata {
    name      = "${var.name}-files"
    namespace = var.namespace
  }

  data = local.files
}

resource "kubernetes_secret_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  data = {
    password = var.clickhouse_password
  }
}

resource "kubernetes_job_v1" "this" {
  metadata {
    name      = "${var.name}-${local.migrations_hash}"
    namespace = var.namespace
  }

  spec {
    backoff_limit = 3

    template {
      metadata {
        labels = { "app.kubernetes.io/name" = var.name }
      }

      spec {
        restart_policy = "Never"
        node_selector  = var.node_selector

        container {
          name  = "migrate"
          image = var.image

          # The database is created by the first migration, so migrate
          # connects to `default` and keeps schema_migrations there.
          # $(CLICKHOUSE_PASSWORD) is expanded by Kubernetes from the env.
          args = [
            "-path=/migrations",
            "-database=clickhouse://${var.clickhouse.host}:${var.clickhouse.native_port}?username=${var.clickhouse.user}&password=$(CLICKHOUSE_PASSWORD)&database=default",
            "up",
          ]

          env {
            name = "CLICKHOUSE_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.this.metadata[0].name
                key  = "password"
              }
            }
          }

          resources {
            requests = { cpu = "50m", memory = "32Mi" }
            limits   = { memory = "128Mi" }
          }

          volume_mount {
            name       = "migrations"
            mount_path = "/migrations"
            read_only  = true
          }
        }

        volume {
          name = "migrations"
          config_map {
            name = kubernetes_config_map_v1.migrations.metadata[0].name
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
  }
}
