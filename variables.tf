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
  description = "The name of this particular deployment, will get added as a prefix to most resources."
  default     = "three-tier-app"
}

variable "database_type" {
  type        = string
  description = "Cloud SQL Database flavor: either 'mysql' or 'postgresql'"
  default     = "postgresql"
  validation {
    condition     = contains(["mysql", "postgresql"], var.database_type)
    error_message = "database_type must be either 'mysql' or 'postgresql'."
  }
}

variable "labels" {
  type        = map(string)
  description = "A map of labels to apply to all resources"
  default     = {
    environment = "dev"
    project     = "three-tier-app"
  }
}

variable "enable_apis" {
  type        = bool
  description = "Whether or not to enable required GCP APIs"
  default     = true
}

variable "run_roles_list" {
  description = "List of IAM roles to grant to the Cloud Run service account"
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
  description = "The password for the MySQL user (only used when database_type = 'mysql')"
  sensitive   = true
}

variable "pg_password" {
  type        = string
  description = "The password for the PostgreSQL user (only used when database_type = 'postgresql')"
  sensitive   = true
}
