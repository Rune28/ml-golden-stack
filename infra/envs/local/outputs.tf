output "temporal_ui_url" {
  value = local.cluster.service_urls["temporal-ui"]
}

output "temporal_frontend_address" {
  value = module.temporal.frontend_address
}
