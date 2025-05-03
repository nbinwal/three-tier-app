data "google_project" "project" {
  project_id = var.project_id
}

locals {
  api_image = var.database_type == "mysql" ? "gcr.io/sic-container-repo/todo-api" : "gcr.io/sic-container-repo/todo-api-postgres:latest"
  fe_image  = "gcr.io/sic-container-repo/todo-fe"

  api_env_vars_postgresql = {
    REDIS_HOST = google_redis_instance.main.host
    DB_HOST    = google_sql_database_instance.main.ip_address[0].ip_address
    DB_USER    = google_service_account.runsa.email
    DB_CONN    = google_sql_database_instance.main.connection_name
    DB_NAME    = "todo"
    REDIS_PORT = "6379"
  }

  api_env_vars_mysql = {
    REDIS_HOST = google_redis_instance.main.host
    DB_HOST    = google_sql_database_instance.main.ip_address[0].ip_address
    DB_USER    = "foo"
    DB_PASS    = var.database_type == "mysql" ? data.google_secret_manager_secret_version.db_password[0].secret_data : ""
