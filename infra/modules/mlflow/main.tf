# MLflow tracking server and model registry. Cloud agnostic: the database and
# the object store come in as inputs. The server proxies artifacts
# (--artifacts-destination), so clients need only its URL, no S3 keys.

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret_v1" "this" {
  metadata {
    name      = "mlflow"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    db_password   = var.db_password
    s3_secret_key = var.s3_secret_key
  }
}

locals {
  name   = "mlflow"
  labels = { "app.kubernetes.io/name" = local.name }
  port   = 5000
  host   = "${local.name}.${var.namespace}.svc"

  # $(DB_PASSWORD) is expanded by Kubernetes from the container env.
  backend_store_uri = "postgresql://${var.db.user}:$(DB_PASSWORD)@${var.db.host}:${var.db.port}/${var.db.database}"

  env = {
    MLFLOW_S3_ENDPOINT_URL = var.s3.endpoint
    AWS_ACCESS_KEY_ID      = var.s3.access_key
    # Background jobs (GenAI scorers, periodic tasks) start a job runner and
    # seven huey consumers, ~2 GiB more. Not used here.
    MLFLOW_SERVER_ENABLE_JOB_EXECUTION = "false"
  }

  secret_env = {
    DB_PASSWORD           = "db_password"
    AWS_SECRET_ACCESS_KEY = "s3_secret_key"
  }
}

resource "kubernetes_service_v1" "this" {
  metadata {
    name      = local.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    type     = var.service.type
    selector = local.labels

    port {
      name        = "http"
      port        = local.port
      target_port = "http"
      node_port   = var.service.node_port
    }
  }
}

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = local.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    replicas = 1

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        node_selector = var.node_selector

        # Creates the tables on an empty database, migrates them after an
        # MLflow upgrade, does nothing otherwise. The server refuses to start
        # on an out-of-date schema, so this runs before it.
        init_container {
          name    = "db-upgrade"
          image   = var.image
          command = ["mlflow", "db", "upgrade", local.backend_store_uri]

          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.this.metadata[0].name
                key  = "db_password"
              }
            }
          }

          resources {
            requests = { cpu = "100m", memory = "256Mi" }
            limits   = { memory = "512Mi" }
          }
        }

        container {
          name  = "mlflow"
          image = var.image

          command = [
            "mlflow", "server",
            "--host", "0.0.0.0",
            "--port", tostring(local.port),
            "--workers", "1",
            "--backend-store-uri", local.backend_store_uri,
            "--artifacts-destination", "s3://${var.s3.bucket}",
            # Host header check against DNS rebinding: the default allows
            # only localhost and private IPs, not the service name.
            "--allowed-hosts", "${local.host},${local.host}:${local.port},localhost:*,127.0.0.1:*",
          ]

          dynamic "env" {
            for_each = local.secret_env
            content {
              name = env.key
              value_from {
                secret_key_ref {
                  name = kubernetes_secret_v1.this.metadata[0].name
                  key  = env.value
                }
              }
            }
          }
          dynamic "env" {
            for_each = local.env
            content {
              name  = env.key
              value = env.value
            }
          }

          port {
            name           = "http"
            container_port = local.port
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            period_seconds = 10
          }

          # Measured: ~450 MiB with job execution off (CLI process + uvicorn).
          resources {
            requests = { cpu = "100m", memory = "512Mi" }
            limits   = { memory = "768Mi" }
          }
        }
      }
    }
  }
}
