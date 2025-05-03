variable "project_id" {
  type        = string
  description = "The project ID to deploy to"
}

variable "region" {
  type        = string
  description = "The Compute Region to deploy to"
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "The Compute Zone to deploy to"
  default     = "us-central1-a"
}

variable "deployment_name" {
  type        = string
  description = "The name of this deployment; prefix for resources"
  default     = "three-tier-app"
}

variable "database_type" {
  type        = string
  description = "Cloud SQL flavor: 'mysql' or 'postgresql'"
  default     = "postgresql"
  validation {
    condition     = contains(["mysql", "postgresql"], var.database_type)
    error_message = "Must be either 'mysql' or 'postgresql'."
  }
}

variable "labels" {
  type        = map(string)
  description = "Labels to apply to all resources"
  default = {
    environment = "dev"
    project     = "three-tier-app"
  }
}

variable "enable_apis" {
  type        = bool
  description = "Enable required GCP APIs"
  default     = true
}

variable "run_roles_list" {
  description = "IAM roles to grant to the Cloud Run service account"
  type        = list(string)
  default     = [
    "roles/iam.serviceAccountUser",
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",
    "roles/redis.viewer",
  ]
}

variable "mysql_password" {
  type        = string
  description = "MySQL user password (when database_type = 'mysql')"
  sensitive   = true
}

variable "pg_password" {
  type        = string
  description = "PostgreSQL user password (when database_type = 'postgresql')"
  sensitive   = true
}
