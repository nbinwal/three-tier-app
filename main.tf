############################################
# main.tf (updated for conditional password auth)
############################################

data "google_project" "project" {
  project_id = var.project_id
}

# ----------------------------------------------------------------
# Locals: choose images based on database type
# ----------------------------------------------------------------
locals {
  api_image = var.database_type == "mysql" ? "gcr.io/sic-container-repo/todo-api" : "gcr.io/sic-container-repo/todo-api-postgres:latest"
  fe_image  = "gcr.io/sic-container-repo/todo-fe"
}

# ----------------------------------------------------------------
# Project Services Module
# ----------------------------------------------------------------
module "project-services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "18.0.0"

  disable_services_on_destroy = false
  project_id                  = var.project_id
  enable_apis                 = var.enable_apis
  activate_apis = [
    "compute.googleapis.com",
    "vpcaccess.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudbuild.googleapis.com",
    "sqladmin.googleapis.com",
    "storage.googleapis.com",
    "run.googleapis.com",
    "redis.googleapis.com",
    "secretmanager.googleapis.com",
    "iamcredentials.googleapis.com"
  ]
}

# ----------------------------------------------------------------
# Service account for Cloud Run
# ----------------------------------------------------------------
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

# ----------------------------------------------------------------
# Secrets: only when using MySQL or Postgres
# ----------------------------------------------------------------
resource "google_secret_manager_secret" "db_password" {
  count     = var.database_type == "mysql" || var.database_type == "postgresql" ? 1 : 0
  secret_id = "${var.deployment_name}-db-password"
  project   = var.project_id
  replication { automatic = true }
}

resource "google_secret_manager_secret_version" "db_password" {
  count       = var.database_type == "mysql" || var.database_type == "postgresql" ? 1 : 0
  secret      = google_secret_manager_secret.db_password[0].id
  secret_data = var.database_type == "postgresql" ? var.pg_password : var.mysql_password
}

data "google_secret_manager_secret_version" "db_password" {
  count   = var.database_type == "mysql" || var.database_type == "postgresql" ? 1 : 0
  secret  = google_secret_manager_secret.db_password[0].name
  version = "latest"
}

# ----------------------------------------------------------------
# VPC, Redis, SQL Instance, etc...
# ----------------------------------------------------------------
resource "google_compute_network" "main" {
  provider                = google-beta
  name                    = "${var.deployment_name}-private-network"
  auto_create_subnetworks = true
  project                 = var.project_id
}

resource "google_compute_global_address" "main" {
  provider      = google-beta
  name          = "${var.deployment_name}-vpc-address"
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
  depends_on              = [google_compute_network.main]
}

resource "google_vpc_access_connector" "main" {
  provider       = google-beta
  project        = var.project_id
  name           = "${var.deployment_name}-vpc-cx"
  ip_cidr_range  = "10.8.0.0/28"
  network        = google_compute_network.main.name
  region         = var.region
  max_throughput = 300

  depends_on = [google_compute_network.main]
}

resource "time_sleep" "wait_before_destroying_network" {
  depends_on       = [google_compute_network.main]
  destroy_duration = "60s"
}

resource "google_redis_instance" "main" {
  project                  = var.project_id
  name                     = "${var.deployment_name}-cache"
  location_id              = var.zone
  region                   = var.region
  memory_size_gb           = 1
  authorized_network       = google_compute_network.main.name
  connect_mode             = "DIRECT_PEERING"
  tier                     = "BASIC"
  transit_encryption_mode  = "DISABLED"
  reserved_ip_range        = "10.137.125.88/29"
  redis_version            = "REDIS_6_X"
  display_name             = "${var.deployment_name}-cache"
  labels                   = var.labels
}

resource "random_id" "id" {
  byte_length = 2
}

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
      private_network = google_compute_network.main.id
    }

    location_preference {
      zone = var.zone
    }
    # We're using password auth, so no IAM database flags here.
  }

  deletion_protection = false
  depends_on          = [google_service_networking_connection.main]
}

# SQL Users
resource "google_sql_user" "mysql_user" {
  count    = var.database_type == "mysql" ? 1 : 0
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = "foo"
  password = var.mysql_password
}

resource "google_sql_user" "postgres_user" {
  count    = var.database_type == "postgresql" ? 1 : 0
  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = "pguser"
  password = var.pg_password
}

resource "google_sql_database" "database" {
  project         = var.project_id
  name            = "todo"
  instance        = google_sql_database_instance.main.name
  deletion_policy = "ABANDON"
}

# Cloud Run Services (API + FE)...
# ...no other changes here
