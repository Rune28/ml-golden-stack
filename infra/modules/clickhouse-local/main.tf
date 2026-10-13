# Single ClickHouse server in its own namespace. Local stand-in for a managed
# ClickHouse (ClickHouse Cloud, Altinity.Cloud): clients reach it only through
# the outputs. No replication, no backups. Databases and tables are created by
# migrations (modules/clickhouse-migrate), not here.

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "random_password" "this" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    password = random_password.this.result
  }
}

locals {
  labels = { "app.kubernetes.io/name" = var.name }

  config_files = {
    "low-memory.xml"       = file("${path.module}/low-memory.xml")
    "low-memory-users.xml" = file("${path.module}/low-memory-users.xml")
  }
}

resource "kubernetes_config_map_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = local.config_files
}

resource "kubernetes_service_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    selector = local.labels

    # HTTP for applications (clickhouse-connect, the Rust client),
    # native protocol for migrate.
    port {
      name        = "http"
      port        = 8123
      target_port = "http"
    }
    port {
      name        = "native"
      port        = 9000
      target_port = "native"
    }
  }
}

resource "kubernetes_stateful_set_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    service_name = kubernetes_service_v1.this.metadata[0].name
    replicas     = 1

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
        # Config files are read at start: restart when they change.
        annotations = {
          "checksum/config" = sha256(jsonencode(local.config_files))
        }
      }

      spec {
        node_selector = var.node_selector

        container {
          name  = "clickhouse"
          image = var.image

          port {
            name           = "http"
            container_port = 8123
          }
          port {
            name           = "native"
            container_port = 9000
          }

          # The image entrypoint replaces the passwordless `default` user
          # with this one. Access management lets it create more users
          # later (a read-only one for be_service).
          env {
            name  = "CLICKHOUSE_USER"
            value = var.user
          }
          env {
            name = "CLICKHOUSE_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.this.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name  = "CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT"
            value = "1"
          }

          readiness_probe {
            http_get {
              path = "/ping"
              port = "http"
            }
            period_seconds = 5
          }

          # max_server_memory_usage is 512 MiB, the rest is the binary
          # itself (~300 MiB resident).
          resources {
            requests = { cpu = "100m", memory = "512Mi" }
            limits   = { memory = "1Gi" }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/clickhouse"
          }
          # Single files, so the entrypoint can still write its own
          # users.d/default-user.xml next to them.
          volume_mount {
            name       = "config"
            mount_path = "/etc/clickhouse-server/config.d/low-memory.xml"
            sub_path   = "low-memory.xml"
            read_only  = true
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/clickhouse-server/users.d/low-memory-users.xml"
            sub_path   = "low-memory-users.xml"
            read_only  = true
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.this.metadata[0].name
          }
        }
      }
    }

    # Cluster default StorageClass.
    volume_claim_template {
      metadata {
        name = "data"
      }

      spec {
        access_modes = ["ReadWriteOnce"]

        resources {
          requests = { storage = var.storage_size }
        }
      }
    }
  }
}
