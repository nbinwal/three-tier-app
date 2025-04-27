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
  description = "Cloud SQL Database flavor, mysql or postgresql"
  default     = "postgresql"
  validation {
    condition     = contains(["mysql", "postgresql"], var.database_type)
    error_message = "Must be either \"mysql\" or \"postgresql\"."
  }
}

variable "labels" {
  type        = map(string)
  description = "A map of labels to apply to contained resources."
  default     = { "three-tier-app" = "true" }
}

variable "enable_apis" {
  type        = bool
  description = "Whether or not to enable underlying APIs in this solution."
  default     = true
}

variable "run_roles_list" {
  description = "The list of IAM roles to grant to the Cloud Run service account."
  type        = list(string)
  default = [
    "roles/cloudsql.instanceUser",
    "roles/cloudsql.client",
    "roles/secretmanager.secretAccessor",    # allows reading secrets
    "roles/iam.serviceAccountUser"          # for IAM auth
  ]
}

# Only used for MySQL; PostgreSQL uses IAM DB auth
variable "mysql_password" {
  type        = string
  description = "The password for the MySQL user; stored in Secret Manager"
  sensitive   = true
  default     = "CHANGE_ME"  # override with real secret input
}

