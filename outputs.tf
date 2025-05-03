output "endpoint" {
  description = "The URL of the deployed frontend (Cloud Run service 'fe')"
  value       = google_cloud_run_service.fe.status[0].url
}

output "sql_instance_name" {
  description = "The name of the Cloud SQL instance created"
  value       = google_sql_database_instance.main.name
}

output "secret_manager_password_secret" {
  description = "The resource name of the Secret Manager secret holding the DB password"
  value       = var.database_type == "mysql" ? google_secret_manager_secret.db_password[0].name : null
}

output "in_console_tutorial_url" {
  description = "Link to the GCP Cloud console walkthrough/tutorial for deploying the three-tier app"
  value       = "https://console.cloud.google.com/products/solutions/deployments?walkthrough_id=panels--sic--three-tier-web-app&project=${var.project_id}"
}
