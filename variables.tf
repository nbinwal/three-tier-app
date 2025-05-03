# Variables: Parameters for customizing the deployment.

variable "project_id" {
  type        = string
  description = "The project ID to deploy to."
}

variable "region" {
  type        = string
  description = "The compute region to deploy to (e.g., us-central1)."
  default     = "us-central1"
}

variable "zone" {
  type        = string
  description = "The compute zone to deploy to (e.g., us-central1-a)."
  default     = "us-central1-a"
}

variable "deployment_name" {
  type        = string
  description = "Name prefix for resources in this deployment."
  default     = "three-tier-app"
}

variable "database_type" {
  type        = string
  description = "Cloud SQL database type to use: \"mysql\" or \"postgresql\"."
  default     = "postgresql"

  validation {
    # Ensure only 'mysql' or 'postgresql' are allowed
    condition     = contains(["mysql", "postgresql"], var.database_type)
    error_message = "Must be either \"mysql\" or \"postgresql\"."
  }
}

variable "labels" {
  type        = map(string)
  description = "A map of labels to apply to all created resources."
  default     = { "three-tier-app" = "true" }
}

variable "enable_apis" {
  type        = bool
  description = "Whether to automatically enable required Google Cloud APIs."
  default     = true
}

variable "run_roles_list" {
  description = "List of IAM roles to grant to the Cloud Run service account."
  type        = list(string)
  default = [
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",
    "roles/iam.serviceAccountUser"
  ]
}

variable "mysql_password" {
  type        = string
  description = "The password for the MySQL user (only used if database_type = \"mysql\")."
  sensitive   = true
  default     = "CHANGE_ME"
}
