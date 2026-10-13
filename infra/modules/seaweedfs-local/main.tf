# Single SeaweedFS instance with its S3 gateway, in its own namespace. Local
# stand-in for S3 / GCS: clients get an endpoint and a key pair through the
# outputs and only speak the S3 API. No replication, no backups.
#
# `weed server` runs master, volume server, filer and S3 gateway in one
# process: enough for one node, and the smallest footprint.

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "random_password" "secret_key" {
  length  = 40
  special = false
}

locals {
  labels     = { "app.kubernetes.io/name" = var.name }
  access_key = "platform"
  host       = "${var.name}.${var.namespace}.svc"

  # One identity with full access, like a root key of a cloud bucket.
  # Read by the S3 gateway at start.
  s3_config = {
    identities = [{
      name        = local.access_key
      credentials = [{ accessKey = local.access_key, secretKey = random_password.secret_key.result }]
      actions     = ["Admin", "Read", "List", "Tagging", "Write"]
    }]
  }

  # HTTP ports; SeaweedFS components also talk gRPC on port + 10000,
  # which `weed shell` in the bucket job needs.
  ports = {
    master = 9333
    filer  = 8888
    s3     = 8333
  }
}

resource "kubernetes_secret_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    "s3.json"  = jsonencode(local.s3_config)
    access_key = local.access_key
    secret_key = random_password.secret_key.result
  }
}

resource "kubernetes_service_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    selector = local.labels

    dynamic "port" {
      for_each = local.ports
      content {
        name        = port.key
        port        = port.value
        target_port = port.value
      }
    }

    dynamic "port" {
      for_each = { for k, v in local.ports : k => v if k != "s3" }
      content {
        name        = "${port.key}-grpc"
        port        = port.value + 10000
        target_port = port.value + 10000
      }
    }
  }
}

# Filer UI on the host. A separate Service, so the main one stays ClusterIP.
resource "kubernetes_service_v1" "filer_ui" {
  count = var.filer_ui_node_port == null ? 0 : 1

  metadata {
    name      = "${var.name}-filer-ui"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    type     = "NodePort"
    selector = local.labels

    port {
      name        = "filer"
      port        = local.ports.filer
      target_port = local.ports.filer
      node_port   = var.filer_ui_node_port
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
        # Restart on credential changes: the S3 config is read only at start.
        annotations = {
          "checksum/s3-config" = sha256(jsonencode(local.s3_config))
        }
      }

      spec {
        node_selector = var.node_selector

        container {
          name  = "seaweedfs"
          image = var.image

          args = [
            "server",
            "-dir=/data",
            # The volume server registers this address with the master.
            "-ip=$(POD_IP)",
            "-ip.bind=0.0.0.0",
            # Default volumes are 30 GB each; small ones fit a small disk.
            "-master.volumeSizeLimitMB=256",
            "-volume.max=16",
            "-filer",
            "-s3",
            "-s3.config=/etc/seaweedfs/s3.json",
          ]

          env {
            name = "POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }

          dynamic "port" {
            for_each = local.ports
            content {
              name           = port.key
              container_port = port.value
            }
          }

          readiness_probe {
            tcp_socket {
              port = "s3"
            }
            period_seconds = 5
          }

          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { memory = "384Mi" }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/seaweedfs"
            read_only  = true
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret_v1.this.metadata[0].name
            items {
              key  = "s3.json"
              path = "s3.json"
            }
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

# Buckets are created once the store is up, as a cloud bucket would be
# created by OpenTofu next to the database. Idempotent: existing buckets are
# skipped, so the job can run again when the list changes.
resource "kubernetes_job_v1" "buckets" {
  count = length(var.buckets) == 0 ? 0 : 1

  metadata {
    # A new list means a new job; an unchanged list leaves the old one alone.
    name      = "${var.name}-buckets-${substr(sha256(join(",", var.buckets)), 0, 8)}"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
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
          name    = "create-buckets"
          image   = var.image
          command = ["/bin/sh", "-ec"]
          args = [<<-EOT
            shell() { echo "$1" | weed shell -master=${local.host}:${local.ports.master} -filer=${local.host}:${local.ports.filer}; }
            existing=$(shell s3.bucket.list)
            for b in ${join(" ", var.buckets)}; do
              if echo "$existing" | grep -qw "$b"; then
                echo "bucket $b exists"
              else
                shell "s3.bucket.create -name $b"
              fi
            done
            # weed shell exits 0 on command errors, so check the result.
            existing=$(shell s3.bucket.list)
            for b in ${join(" ", var.buckets)}; do
              echo "$existing" | grep -qw "$b" || { echo "bucket $b is missing" >&2; exit 1; }
            done
          EOT
          ]

          resources {
            requests = { cpu = "50m", memory = "32Mi" }
            limits   = { memory = "128Mi" }
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
  }

  depends_on = [kubernetes_stateful_set_v1.this]
}
