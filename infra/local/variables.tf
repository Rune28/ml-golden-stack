variable "cluster_name" {
  description = "Name of the kind cluster."
  type        = string
  default     = "gold"
}

variable "node_image" {
  description = "kindest/node image. Pinned to the default image of kind v0.31, the version bundled into the tehcyx/kind provider v0.11."
  type        = string
  default     = "kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f"
}

variable "node_pools" {
  description = <<-EOT
    Worker node pools. Each pool mimics a cloud node group: every node gets the
    label `node-pool = <pool name>` plus the pool's own labels and taints.
    Kueue ResourceFlavors will select pools by these labels.
  EOT
  type = map(object({
    count  = number
    labels = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))

  default = {
    cpu = {
      count  = 1
      labels = { "capacity-type" = "on-demand" }
    }
    # No real GPU locally: this pool only reproduces the scheduling rules
    # of a GPU node group (label + taint), workloads still run on CPU.
    gpu-sim = {
      count  = 1
      labels = { "capacity-type" = "spot" }
      taints = [{ key = "nvidia.com/gpu", value = "present", effect = "NoSchedule" }]
    }
  }

  validation {
    condition     = alltrue([for p in values(var.node_pools) : p.count >= 0])
    error_message = "Node pool count must be zero or greater."
  }

  validation {
    condition = alltrue(flatten([
      for p in values(var.node_pools) : [
        for t in p.taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)
      ]
    ]))
    error_message = "Taint effect must be NoSchedule, PreferNoSchedule or NoExecute."
  }
}

variable "port_mappings" {
  description = "NodePort services exposed on 127.0.0.1 of the host, keyed by service name."
  type = map(object({
    node_port = number
    host_port = number
  }))

  default = {
    temporal-ui   = { node_port = 30080, host_port = 8080 }
    mlflow        = { node_port = 30500, host_port = 5000 }
    minio-console = { node_port = 30901, host_port = 9001 }
  }

  validation {
    condition     = alltrue([for m in values(var.port_mappings) : m.node_port >= 30000 && m.node_port <= 32767])
    error_message = "node_port must be in the NodePort range 30000-32767."
  }
}
