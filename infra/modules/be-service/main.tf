# Backend of the pipeline page. Talks to ClickHouse (Add data, stats),
# Temporal (starts Train and Run) and MLflow (model versions).

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret_v1" "this" {
  metadata {
    name      = "be-service"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    CLICKHOUSE_PASSWORD = var.clickhouse_password
  }
}

locals {
  chart_dir      = "${path.module}/../../charts/be-service"
  chart_checksum = sha256(join("", [for f in sort(fileset(local.chart_dir, "**")) : filesha256("${local.chart_dir}/${f}")]))
  image          = regex("^(.+):([^:/]+)$", var.image)
}

resource "helm_release" "this" {
  name      = "be-service"
  namespace = kubernetes_namespace_v1.this.metadata[0].name
  chart     = local.chart_dir

  wait    = true
  timeout = 300

  values = [yamlencode({
    # helm does not notice edits of a local chart: a checksum of its files
    # in the values makes every edit an upgrade.
    chartChecksum = local.chart_checksum
    podAnnotations = {
      "checksum/settings" = sha256(jsonencode([kubernetes_secret_v1.this.data]))
    }
    image = {
      repository = local.image[0]
      tag        = local.image[1]
    }
    env = {
      CLICKHOUSE_URL      = "http://${var.clickhouse.host}:${var.clickhouse.http_port}"
      CLICKHOUSE_USER     = var.clickhouse.user
      CLICKHOUSE_DATABASE = "ml_data"
      TEMPORAL_ADDRESS    = "http://${var.temporal_address}"
      TEMPORAL_NAMESPACE  = "default"
      MLFLOW_URL          = var.mlflow_tracking_uri
    }
    secretName = kubernetes_secret_v1.this.metadata[0].name
    service = {
      type     = var.service.type
      nodePort = var.service.node_port
    }
    nodeSelector = var.node_selector
  })]
}
