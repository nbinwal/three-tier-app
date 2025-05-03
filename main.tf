data "google_project" "project" {
  project_id = var.project_id
}

# Network Resources (Must be declared first)
resource "google_compute_network" "main" {
  provider                = google-beta
  name                    = "${var.deployment_name}-private-network"
  auto_create_subnetworks = true
  project                 = var.project_id
}

resource "google_compute_global_address" "main" {
  name          = "${var.deployment_name}-vpc-address"
  provider      = google-beta
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.main.name
  project       = var.project_id
}

resource "google_service_networking_connection" "main" {
  network                 = google_compute_network.main.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.main.name]
}

# Redis Instance
resource "google_redis_instance" "main" {
  authorized_network      = google_compute_network.main.name
  connect_mode            = "DIRECT_PEERING"
  location_id             = var.zone
  memory_size_gb          = 1
  name                    = "${var.deployment_name}-cache"
  project                 = var.project_id
  redis_version           = "REDIS_6_X"
  region                  = var.region
  tier                    = "BASIC"
  transit_encryption_mode = "DISABLED"
  labels                  = var.labels
}

# SQL Database Instance
resource "google_sql_database_instance" "main" {
  name             = "${var.deployment_name}-db-${random_id.id.hex}"
  database_version = var.database_type == "mysql" ? "MYSQL_8_0" : "POSTGRES_14"
  region           = var.region
  project          = var.project_id

  settings {
    tier            = "db-g1-small"
    disk_autoresize = true
    disk_size       = 10
    disk_type       = "PD_SSD"
    user_labels     = var.labels

    ip_configuration {
      ipv4_enabled    = false
      private_network = "projects/${var.project_id}/global/networks/${google_compute_network.main.name}"
    }

    dynamic "database_flags" {
      for_each = var.database_type == "postgresql" ? [1] : []
      content {
        name  = "cloudsql.iam_authentication"
        value = "on"
      }
    }
  }

  deletion_protection = false
  depends_on          = [google_service_networking_connection.main]
}

# Service Account and IAM
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

# Secret Manager (MySQL Only)
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
  depends_on  = [google_sql_database_instance.main]
}

data "google_secret_manager_secret_version" "db_password" {
  count     = var.database_type == "mysql" ? 1 : 0
  secret    = google_secret_manager_secret.db_password[0].name
  depends_on = [google_secret_manager_secret_version.db_password]
}

# Database User
resource "google_sql_user" "main" {
  project        = var.project_id
  instance       = google_sql_database_instance.main.name
  deletion_policy = "ABANDON"

  # Fixed ternary expression formatting
  name = (
    var.database_type == "postgresql" ?
    "${google_service_account.runsa.account_id}@${var.project_id}.iam" :
    "foo"
  )

  type = var.database_type == "postgresql" ? "CLOUD_IAM_SERVICE_ACCOUNT" : null
  password = var.database_type == "mysql" ? data.google_secret_manager_secret_version.db_password[0].secret_data : null
}

# Database
resource "google_sql_database" "database" {
  project         = var.project_id
  name            = "todo"
  instance        = google_sql_database_instance.main.name
  deletion_policy = "ABANDON"
}

# Cloud Run Services
resource "google_cloud_run_service" "api" {
  name     = "${var.deployment_name}-api"
  provider = google-beta
  location = var.region
  project  = var.project_id

  template {
    spec {
      service_account_name = google_service_account.runsa.email
      containers {
        image = local.api_image
        dynamic "env" {
          for_each = var.database_type == "postgresql" ? local.api_env_vars_postgresql : local.api_env_vars_mysql
          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"         = "8"
        "run.googleapis.com/cloudsql-instances"    = google_sql_database_instance.main.connection_name
        "run.googleapis.com/vpc-access-connector"  = google_vpc_access_connector.main.id
      }
    }
  }
  depends_on = [google_sql_user.main]
}

resource "google_cloud_run_service" "fe" {
  name     = "${var.deployment_name}-fe"
  location = var.region
  project  = var.project_id

  template {
    spec {
      service_account_name = google_service_account.runsa.email
      containers {
        image = local.fe_image
        ports { container_port = 80 }
        env {
          name  = "ENDPOINT"
          value = google_cloud_run_service.api.status[0].url
        }
      }
    }
  }
}

# IAM Access
resource "google_cloud_run_service_iam_member" "noauth_api" {
  location = google_cloud_run_service.api.location
  project  = google_cloud_run_service.api.project
  service  = google_cloud_run_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_service_iam_member" "noauth_fe" {
  location = google_cloud_run_service.fe.location
  project  = google_cloud_run_service.fe.project
  service  = google_cloud_run_service.fe.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Locals (Must be declared after all resources)
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
    todo_pass  = try(data.google_secret_manager_secret_version.db_password[0].secret_data, null)
    todo_name  = "todo"
    REDISPORT  = "6379"
  }
}

# Random ID
resource "random_id" "id" {
  byte_length = 2
}

# VPC Connector
resource "google_vpc_access_connector" "main" {
  provider       = google-beta
  project        = var.project_id
  name           = "${var.deployment_name}-vpc-cx"
  ip_cidr_range  = "10.8.0.0/28"
  network        = google_compute_network.main.name
  region         = var.region
  max_throughput = 300
}
