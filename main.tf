data "google_project" "project" {
  project_id = var.project_id
}

locals {
  api_image = var.database_type == "mysql" ? "gcr.io/sic-container-repo/todo-api" : "gcr.io/sic-container-repo/todo-api-postgres:latest"
  fe_image  = "gcr.io/sic-container-repo/todo-fe"

  api_env_vars_postgresql = {
    redis_host = google_redis_instance.main.host
    db_host    = google_sql_database_instance.main.ip_address[0].ip_address
    db_user    = google_service_account.runsa.email
    db_conn    = google_sql_database_instance.main.connection_name
    db_name    = "todo"
    redis_port = "6379"
  }

  api_env_vars_mysql = {
    REDISHOST  = google_redis_instance.main.host
    todo_host  = google_sql_database_instance.main.ip_address[0].ip_address
    todo_user  = "foo"
    todo_pass  = var.database_type == "mysql" ? data.google_secret_manager_secret_version.db_password[0].secret_data : null
    todo_name  = "todo"
    REDISPORT  = "6379"
  }
}

module "project-services" {
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "18.0.0"
  project_id                  = var.project_id
  disable_services_on_destroy = false
  enable_apis                 = var.enable_apis
  activate_apis = [
    "compute.googleapis.com",
    "cloudapis.googleapis.com",
    "vpcaccess.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudbuild.googleapis.com",
    "sql-component.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "run.googleapis.com",
    "redis.googleapis.com",
    "secretmanager.googleapis.com",
    "iamcredentials.googleapis.com"
  ]
}

resource "google_service_account" "runsa" {
  project      = var.project_id
  account_id   = "${var.deployment_name}-run-sa"
  display_name = "Service Account for Cloud Run"
}

resource "google_project_iam_member" "runsa_roles" {
  for_each = toset(var.run_roles_list)
  project  = data.google_project.project.number
  role     = each.key
  member   = "serviceAccount:${google_service_account.runsa.email}"
}

resource "google_secret_manager_secret" "db_password" {
  count     = var.database_type == "mysql" ? 1 : 0
  secret_id = "${var.deployment_name}-db-password"
  project   = var.project_id
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  count       = var.database_type == "mysql" ? 1 : 0
  secret      = google_secret_manager_secret.db_password[0].id
  secret_data = var.mysql_password

  # Add explicit dependency
  depends_on = [google_sql_database_instance.main]
}

data "google_secret_manager_secret_version" "db_password" {
  count   = var.database_type == "mysql" ? 1 : 0
  secret  = google_secret_manager_secret.db_password[0].name
  
  # Critical fix: Wait for secret version creation
  depends_on = [google_secret_manager_secret_version.db_password]
}

# ... [Keep all other resources identical until sql_user] ...

resource "google_sql_user" "main" {
  project        = var.project_id
  instance       = google_sql_database_instance.main.name
  deletion_policy = "ABANDON"

  name = (
    var.database_type == "postgresql" 
    ? "${google_service_account.runsa.account_id}@${var.project_id}.iam" 
    : "foo"
  )

  type = var.database_type == "postgresql" ? "CLOUD_IAM_SERVICE_ACCOUNT" : null
  
  # Use secret data instead of direct variable
  password = var.database_type == "mysql" ? data.google_secret_manager_secret_version.db_password[0].secret_data : null
  
  # Add explicit dependency
  depends_on = [google_secret_manager_secret_version.db_password]
}

# ... [Rest of the file remains unchanged] ...
