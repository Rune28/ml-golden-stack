locals {
  # Both stores live in the same Postgres; the chart's schema job creates the
  # databases and applies migrations on every install and upgrade.
  temporal_sql_store = {
    createDatabase  = true
    manageSchema    = true
    pluginName      = "postgres12"
    driverName      = "postgres12"
    connectAddr     = "${kubernetes_service_v1.temporal_postgres.metadata[0].name}.${kubernetes_namespace_v1.temporal.metadata[0].name}.svc:5432"
    connectProtocol = "tcp"
    user            = "temporal"
    existingSecret  = kubernetes_secret_v1.temporal_db.metadata[0].name
    secretKey       = "password"
    maxConns        = 20
    maxIdleConns    = 20
    maxConnLifetime = "1h"
  }

  temporal_values = {
    server = {
      nodeSelector = var.platform_node_selector
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }

      config = {
        persistence = {
          numHistoryShards = var.temporal_num_history_shards
          datastores = {
            default    = { sql = merge(local.temporal_sql_store, { databaseName = "temporal" }) }
            visibility = { sql = merge(local.temporal_sql_store, { databaseName = "temporal_visibility" }) }
          }
        }

        namespaces = {
          create = true
          # The chart recommends plain jobs over post-install hooks under Terraform.
          useHelmHooks = false
          namespace    = var.temporal_namespaces
        }
      }
    }

    # Also used by the schema and namespace jobs.
    admintools = {
      nodeSelector = var.platform_node_selector
    }

    web = {
      nodeSelector = var.platform_node_selector
      service = {
        type     = "NodePort"
        nodePort = var.temporal_ui_node_port
      }
    }
  }
}

resource "helm_release" "temporal" {
  name       = "temporal"
  namespace  = kubernetes_namespace_v1.temporal.metadata[0].name
  repository = "https://go.temporal.io/helm-charts"
  chart      = "temporal"
  version    = var.temporal_chart_version

  # First install pulls the server, admin-tools and UI images.
  timeout = 900
  wait    = true

  values = [yamlencode(local.temporal_values)]

  # The schema job runs as a pre-install hook and needs a running database.
  depends_on = [kubernetes_stateful_set_v1.temporal_postgres]
}
