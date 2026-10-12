# Single Postgres instance for the Temporal persistence and visibility stores.
# Local stand-in for RDS: no replication, no backups.

resource "kubernetes_namespace_v1" "temporal" {
  metadata {
    name = "temporal"
  }
}

resource "random_password" "temporal_db" {
  length  = 32
  special = false
}

# Shared by Postgres (superuser password) and the Temporal chart (`existingSecret`).
resource "kubernetes_secret_v1" "temporal_db" {
  metadata {
    name      = "temporal-db"
    namespace = kubernetes_namespace_v1.temporal.metadata[0].name
  }

  data = {
    password = random_password.temporal_db.result
  }
}

locals {
  postgres_labels = { "app.kubernetes.io/name" = "temporal-postgres" }
}

resource "kubernetes_service_v1" "temporal_postgres" {
  metadata {
    name      = "temporal-postgres"
    namespace = kubernetes_namespace_v1.temporal.metadata[0].name
    labels    = local.postgres_labels
  }

  spec {
    selector = local.postgres_labels

    port {
      name        = "postgres"
      port        = 5432
      target_port = "postgres"
    }
  }
}

resource "kubernetes_stateful_set_v1" "temporal_postgres" {
  metadata {
    name      = "temporal-postgres"
    namespace = kubernetes_namespace_v1.temporal.metadata[0].name
    labels    = local.postgres_labels
  }

  spec {
    service_name = kubernetes_service_v1.temporal_postgres.metadata[0].name
    replicas     = 1

    selector {
      match_labels = local.postgres_labels
    }

    template {
      metadata {
        labels = local.postgres_labels
      }

      spec {
        node_selector = var.platform_node_selector

        container {
          name  = "postgres"
          image = var.postgres_image

          port {
            name           = "postgres"
            container_port = 5432
          }

          # The `temporal` role is the superuser, so the chart's schema job can
          # create both the `temporal` and `temporal_visibility` databases.
          env {
            name  = "POSTGRES_USER"
            value = "temporal"
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.temporal_db.metadata[0].name
                key  = "password"
              }
            }
          }
          # Subdirectory, so initdb does not trip over files at the volume root.
          env {
            name  = "PGDATA"
            value = "/var/lib/postgresql/data/pgdata"
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "temporal"]
            }
            period_seconds = 5
          }

          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { memory = "512Mi" }
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/postgresql/data"
          }
        }
      }
    }

    # kind's default `standard` StorageClass (local-path provisioner).
    volume_claim_template {
      metadata {
        name = "data"
      }

      spec {
        access_modes = ["ReadWriteOnce"]

        resources {
          requests = { storage = var.postgres_storage_size }
        }
      }
    }
  }
}
