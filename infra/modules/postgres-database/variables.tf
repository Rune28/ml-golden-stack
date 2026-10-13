variable "name" {
  description = "Name of the database and of its owner role."
  type        = string

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.name))
    error_message = "Lowercase letters, digits and underscores, starting with a letter or underscore."
  }
}

variable "namespace" {
  description = "Namespace the setup job runs in: the one of the Postgres server, where the admin credentials belong."
  type        = string
}

variable "postgres" {
  description = "Admin connection to the server (output of postgres-local, or a managed database)."
  type = object({
    host = string
    port = number
    user = string
  })
}

variable "postgres_password" {
  type      = string
  sensitive = true
}

variable "image" {
  description = "Any image with psql."
  type        = string
  default     = "postgres:17.11-alpine"
}

variable "node_selector" {
  type    = map(string)
  default = {}
}
