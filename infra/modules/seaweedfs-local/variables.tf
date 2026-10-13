variable "namespace" {
  description = "Namespace for the object store, separate from its clients."
  type        = string
  default     = "seaweedfs"
}

variable "name" {
  description = "Name of the StatefulSet, Service and Secret."
  type        = string
  default     = "seaweedfs"
}

variable "image" {
  type    = string
  default = "chrislusf/seaweedfs:4.48"
}

variable "storage_size" {
  type    = string
  default = "5Gi"
}

variable "buckets" {
  description = "Buckets created after the store is up."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for b in var.buckets : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", b))])
    error_message = "Bucket names follow S3 rules: 3-63 characters, lowercase letters, digits, dots and hyphens."
  }
}

variable "filer_ui_node_port" {
  description = "NodePort of the filer web UI (file browser). Null keeps the UI inside the cluster."
  type        = number
  default     = null
}

variable "node_selector" {
  type    = map(string)
  default = {}
}
