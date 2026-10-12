# Advertises the node GPUs to Kubernetes as the `nvidia.com/gpu` resource.
# Needed on kind (gpu_mode = nvidia) and EKS; GKE installs its own.
#
# Expects GPU nodes labelled `nvidia.com/gpu.present=true` (the chart's node
# affinity) and nvidia as the default containerd runtime on them.

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "this" {
  name       = "nvidia-device-plugin"
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = var.chart_version
  wait       = true
}
