# Local environment on the kind cluster (infra/clusters/kind).
# Only wiring and local choices here; the services themselves are in infra/modules.

locals {
  # Platform services stay off the GPU pool, which is reserved for model steps.
  platform_node_selector = { "node-pool" = "cpu" }
}

# In the cloud this is a managed database (RDS, Cloud SQL) instead.
module "postgres" {
  source = "../../modules/postgres-local"

  node_selector = local.platform_node_selector
}

module "temporal" {
  source = "../../modules/temporal"

  db = {
    host = module.postgres.host
    port = module.postgres.port
    user = module.postgres.user
  }
  db_password = module.postgres.password

  # Small to keep the footprint low; cannot be changed later without
  # recreating the database.
  num_history_shards = 4
  node_selector      = local.platform_node_selector

  # Exposed on the host through the kind port mapping `temporal-ui`.
  web_service = {
    type     = "NodePort"
    nodePort = var.temporal_ui_node_port
  }
}
