# A database and its owner role on an existing Postgres server, created by a
# one-off Job with psql. Same inputs for the in-cluster Postgres and a managed
# one: the client gets its own database and user, never the admin account.

resource "random_password" "this" {
  length  = 32
  special = false
}

locals {
  job_name = replace("pg-db-${var.name}", "_", "-")
}

resource "kubernetes_secret_v1" "this" {
  metadata {
    name      = local.job_name
    namespace = var.namespace
  }

  data = {
    admin_password = var.postgres_password
    password       = random_password.this.result
  }
}

resource "kubernetes_job_v1" "this" {
  metadata {
    # Runs again only when the database or the password changes.
    name      = "${local.job_name}-${substr(sha256("${var.name}/${random_password.this.result}"), 0, 8)}"
    namespace = var.namespace
  }

  spec {
    # Retries cover the time the server needs to start.
    backoff_limit = 6

    template {
      metadata {}

      spec {
        restart_policy = "OnFailure"
        node_selector  = var.node_selector

        container {
          name    = "psql"
          image   = var.image
          command = ["/bin/sh", "-ec"]
          # Idempotent: CREATE ROLE / DATABASE have no IF NOT EXISTS, so the
          # statement is generated only when missing and run with \gexec.
          # ALTER ROLE keeps the password in sync with the Secret.
          args = [<<-EOT
            psql -v ON_ERROR_STOP=1 -v name="${var.name}" -v pw="$DB_PASSWORD" <<'SQL'
            SELECT format('CREATE ROLE %I LOGIN', :'name')
              WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'name') \gexec
            SELECT format('ALTER ROLE %I PASSWORD %L', :'name', :'pw') \gexec
            SELECT format('CREATE DATABASE %I OWNER %I', :'name', :'name')
              WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'name') \gexec
            SQL
          EOT
          ]

          env {
            name  = "PGHOST"
            value = var.postgres.host
          }
          env {
            name  = "PGPORT"
            value = tostring(var.postgres.port)
          }
          env {
            name  = "PGUSER"
            value = var.postgres.user
          }
          env {
            name = "PGPASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.this.metadata[0].name
                key  = "admin_password"
              }
            }
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.this.metadata[0].name
                key  = "password"
              }
            }
          }

          resources {
            requests = { cpu = "50m", memory = "32Mi" }
            limits   = { memory = "64Mi" }
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
