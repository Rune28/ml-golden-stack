locals {
  # Kept inside the module (gitignored) so the user's ~/.kube/config stays untouched.
  kubeconfig_path = abspath("${path.module}/.kubeconfig")

  gpu_pools = [for name, pool in var.node_pools : name if pool.gpu && pool.count > 0]

  workers = flatten([
    for pool_name, pool in var.node_pools : [
      for i in range(pool.count) : {
        labels = merge({ "node-pool" = pool_name }, pool.labels, pool.gpu ? { "gpu-simulated" = "true" } : {})
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

# Makes GPU nodes look like cloud GPU nodes to the scheduler: they advertise
# a fake `nvidia.com/gpu` resource. Runs on the host, needs kubectl.
resource "terraform_data" "gpu_nodes" {
  count = length(local.gpu_pools) > 0 ? 1 : 0

  triggers_replace = [kind_cluster.this.id, var.simulated_gpus_per_node]

  provisioner "local-exec" {
    command = "${path.module}/scripts/setup-gpu-nodes.sh"
    environment = {
      KUBECONFIG     = local.kubeconfig_path
      NODE_SELECTOR  = "node-pool in (${join(",", local.gpu_pools)})"
      SIMULATED_GPUS = var.simulated_gpus_per_node
    }
  }
}
