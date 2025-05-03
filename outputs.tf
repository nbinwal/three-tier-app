output "endpoint" {
  value       = google_cloud_run_service.fe.status[0].url
  description = "The URL of the front end service"
}

output "sql_instance_name" {
  value       = google_sql_database_instance.main.name
  description = "The name of the Cloud SQL instance"
}

output "secret_manager_password_secret" {
  value       = var.database_type == "mysql" ? google_secret_manager_secret.db_password[0].name : null
  description = "The Secret Manager secret resource for the MySQL password (only available when database_type is mysql)"
}

output "in_console_tutorial_url" {
  value       = "https://console.cloud.google.com/products/solutions/deployments?walkthrough_id=panels--sic--three-tier-web-app&project=${var.project_id}"
  description = "Console URL to launch the Three Tier App tutorial"
}
