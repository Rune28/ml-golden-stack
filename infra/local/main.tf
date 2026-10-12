locals {
  # Kept inside the module (gitignored) so the user's ~/.kube/config stays untouched.
  kubeconfig_path = abspath("${path.module}/.kubeconfig")

  workers = flatten([
    for pool_name, pool in var.node_pools : [
      for i in range(pool.count) : {
        labels = merge({ "node-pool" = pool_name }, pool.labels)
        taints = pool.taints
      }
    ]
  ])
}

resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  wait_for_ready  = true
  kubeconfig_path = local.kubeconfig_path

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Control plane keeps its NoSchedule taint (kind adds it when workers exist),
    # so platform and pipeline pods land on the worker pools.
    node {
      role = "control-plane"

      # NodePorts are reachable on every node, mapping them here is enough.
      dynamic "extra_port_mappings" {
        for_each = var.port_mappings
        content {
          container_port = extra_port_mappings.value.node_port
          host_port      = extra_port_mappings.value.host_port
          listen_address = "127.0.0.1"
          protocol       = "TCP"
        }
      }
    }

    dynamic "node" {
      for_each = local.workers
      content {
        role   = "worker"
        labels = node.value.labels

        kubeadm_config_patches = length(node.value.taints) == 0 ? [] : [
          yamlencode({
            kind             = "JoinConfiguration"
            nodeRegistration = { taints = node.value.taints }
          })
        ]
      }
    }
  }
}
