variable "namespace" {
  type    = string
  default = "mlflow"
}

variable "image" {
  description = "The -full variant ships psycopg2 and boto3, the plain one has neither."
  type        = string
  default     = "ghcr.io/mlflow/mlflow:v3.17.0-full"
}

variable "db" {
  description = "Postgres database of MLflow's own (output of postgres-database), or a managed one."
  type = object({
    host     = string
    port     = number
    database = string
    user     = string
  })
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "s3" {
  description = "Object store for artifacts: endpoint and bucket. In AWS endpoint is null and the bucket is a real S3 bucket."
  type = object({
    endpoint   = string
    bucket     = string
    access_key = string
  })
}

variable "s3_secret_key" {
  type      = string
  sensitive = true
}

variable "service" {
  description = "Service of the UI and API: ClusterIP, NodePort with node_port, ..."
  type = object({
    type      = string
    node_port = optional(number)
  })
  default = { type = "ClusterIP" }
}

variable "node_selector" {
  type    = map(string)
  default = {}
}
