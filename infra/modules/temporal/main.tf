# Temporal server and UI from the official chart. Cloud agnostic: the database
# and the way the UI is exposed come in as inputs.

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret_v1" "db" {
  metadata {
    name      = "temporal-db"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    password = var.db_password
  }
}

locals {
  # Both stores live in the same Postgres; the chart's schema job creates the
  # databases and applies migrations on every install and upgrade.
  sql_store = {
    createDatabase  = true
    manageSchema    = true
    pluginName      = "postgres12"
    driverName      = "postgres12"
    connectAddr     = "${var.db.host}:${var.db.port}"
    connectProtocol = "tcp"
    user            = var.db.user
    existingSecret  = kubernetes_secret_v1.db.metadata[0].name
    secretKey       = "password"
    maxConns        = 20
    maxIdleConns    = 20
    maxConnLifetime = "1h"
  }

  values = {
    server = {
      replicaCount = var.replicas
      nodeSelector = var.node_selector
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }

      config = {
        persistence = {
          numHistoryShards = var.num_history_shards
          datastores = {
            default    = { sql = merge(local.sql_store, { databaseName = "temporal" }) }
            visibility = { sql = merge(local.sql_store, { databaseName = "temporal_visibility" }) }
          }
        }

        namespaces = {
          create = true
          # The chart recommends plain jobs over post-install hooks under Terraform.
          useHelmHooks = false
          namespace    = var.namespaces
        }
      }
    }

    # Also used by the schema and namespace jobs.
    admintools = {
      nodeSelector = var.node_selector
    }

    web = {
      replicaCount = var.replicas
      nodeSelector = var.node_selector
      service      = var.web_service
    }
  }
}

resource "helm_release" "this" {
  name       = "temporal"
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "https://go.temporal.io/helm-charts"
  chart      = "temporal"
  version    = var.chart_version

  # First install pulls the server, admin-tools and UI images.
  timeout = 900
  wait    = true

  values = [yamlencode(local.values)]
}
