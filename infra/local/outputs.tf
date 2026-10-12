output "cluster_name" {
  value = kind_cluster.this.name
}

output "kubeconfig_context" {
  value = "kind-${kind_cluster.this.name}"
}

output "kubeconfig_path" {
  description = "Run `export KUBECONFIG=<this path>` to use kubectl against the cluster."
  value       = kind_cluster.this.kubeconfig_path
}

output "endpoint" {
  value = kind_cluster.this.endpoint
}

output "service_urls" {
  value = { for name, m in var.port_mappings : name => "http://127.0.0.1:${m.host_port}" }
}

# Consumed by the platform layer (helm/kubernetes providers).
output "client_certificate" {
  value     = kind_cluster.this.client_certificate
  sensitive = true
}

output "client_key" {
  value     = kind_cluster.this.client_key
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = kind_cluster.this.cluster_ca_certificate
  sensitive = true
}
