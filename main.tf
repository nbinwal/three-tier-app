# ---------------------------------------------------------------------------------
# Data Source: Get information about the GCP project where resources will be created
data "google_project" "project" {
  project_id = var.project_id   # The GCP project ID is passed in via a variable
}

# ---------------------------------------------------------------------------------
# Locals: Define computed values or shortcuts used within this configuration
locals {
  # Choose the container image for the API based on the database type
  api_image = var.database_type == "mysql" 
    ? "gcr.io/sic-container-repo/todo-api" 
    : "gcr.io/sic-container-repo/todo-api-postgres:latest"

  # Frontend container image (fixed in this example)
  fe_image  = "gcr.io/sic-container-repo/todo-fe"

  # Environment variables for the API when using PostgreSQL
  api_env_vars_postgresql = {
    redis_host = google_redis_instance.main.host                           # Redis host IP/name
    db_host    = google_sql_database_instance.main.ip_address[0].ip_address  # Cloud SQL IP address
    db_user    = google_service_account.runsa.email                         # Service account email used for DB auth
    db_conn    = google_sql_database_instance.main.connection_name          # Cloud SQL instance connection name
    db_name    = "todo"                                                     # Database name to use
    redis_port = "6379"                                                     # Default Redis port
  }

  # Environment variables for the API when using MySQL
  api_env_vars_mysql = {
    REDISHOST = google_redis_instance.main.host                             # Redis host IP/name
    todo_host = google_sql_database_instance.main.ip_address[0].ip_address  # Cloud SQL IP address
    todo_user = "foo"                                                       # MySQL username (hardcoded as "foo")
    todo_pass = data.google_secret_manager_secret_version.db_password.secret_data  # MySQL user password from Secret Manager
    todo_name = "todo"                                                      # Database name to use
    REDISPORT = "6379"                                                      # Default Redis port
  }
}

# ---------------------------------------------------------------------------------
# Module: Enable GCP project services/APIs using a standard module (Project Factory)
module "project-services" {
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "18.0.0"
  project_id                  = var.project_id       # GCP project to configure
  disable_services_on_destroy = false                # Keep APIs enabled even if destroying
  enable_apis                 = var.enable_apis      # Use variable to decide if APIs should be enabled
  activate_apis = [
    "compute.googleapis.com",               # Compute Engine API for networks, instances, etc.
    "cloudapis.googleapis.com",             # Google Cloud APIs, general
    "vpcaccess.googleapis.com",             # Serverless VPC Access
    "servicenetworking.googleapis.com",     # Service Networking for VPC peering (used by Cloud SQL, Redis, etc.)
    "cloudbuild.googleapis.com",            # Cloud Build for building container images
    "sql-component.googleapis.com",         # (Possibly redundant) Cloud SQL API
    "sqladmin.googleapis.com",              # Cloud SQL Admin API
    "storage.googleapis.com",               # Cloud Storage for buckets (if needed)
    "run.googleapis.com",                   # Cloud Run for serverless services
    "redis.googleapis.com",                 # Memorystore Redis API
    "secretmanager.googleapis.com",         # Secret Manager for storing secrets
    "iamcredentials.googleapis.com"         # IAM Credentials API for service accounts
  ]
}

# ---------------------------------------------------------------------------------
# Resource: Google Service Account for Cloud Run services
resource "google_service_account" "runsa" {
  project      = var.project_id
  account_id   = "${var.deployment_name}-run-sa"   # Unique ID for this service account
  display_name = "Service Account for Cloud Run"
}

# Assign IAM roles to the Cloud Run service account based on a list of roles
resource "google_project_iam_member" "runsa_roles" {
  for_each = toset(var.run_roles_list)    # Loop over each role in the list (prevents repeating code)
  project  = data.google_project.project.number  # Numeric project ID from data source
  role     = each.key                            # IAM role string (e.g., "roles/cloudsql.client")
  member   = "serviceAccount:${google_service_account.runsa.email}"  
  # The member is the service account's email, giving it the specified role
}

# ---------------------------------------------------------------------------------
# Resource: Secret Manager - create a secret to hold the database password
resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.deployment_name}-db-password"  # Name/ID of the secret
  project   = var.project_id
  replication {
    automatic = true   # Automatically replicate the secret across regions
  }
}

# Add a secret version with the actual password data (for MySQL)
resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id  # References the secret above
  secret_data = var.mysql_password                           # The actual password value from variables
}

# Data: Retrieve the latest version of the secret to use it later (for API/environment vars)
data "google_secret_manager_secret_version" "db_password" {
  secret = google_secret_manager_secret.db_password.name   # Use the secret we just created
}

# ---------------------------------------------------------------------------------
# Resource: Create a Google Compute VPC network (default auto-subnet mode)
resource "google_compute_network" "main" {
  provider                = google-beta
  name                    = "${var.deployment_name}-private-network"
  auto_create_subnetworks = true    # Automatically create subnetworks in each region
  project                 = var.project_id
}

# Resource: Reserve an internal IP range for VPC peering (used by services like Cloud SQL)
resource "google_compute_global_address" "main" {
  name          = "${var.deployment_name}-vpc-address"
  provider      = google-beta
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16                     # /16 range
  network       = google_compute_network.main.name
  project       = var.project_id
}

# Connect the reserved range to Google's managed service networking
resource "google_service_networking_connection" "main" {
  network                 = google_compute_network.main.self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.main.name]
  depends_on              = [google_compute_network.main]  # Ensure network exists first
}

# ---------------------------------------------------------------------------------
# Resource: VPC Access Connector (allows Cloud Run to access VPC resources privately)
resource "google_vpc_access_connector" "main" {
  provider      = google-beta
  project       = var.project_id
  name          = "${var.deployment_name}-vpc-cx"
  ip_cidr_range = "10.8.0.0/28"    # Small CIDR block for connector
  network       = google_compute_network.main.name
  region        = var.region
  max_throughput = 300            # Max bandwidth in Mbps
  depends_on    = [time_sleep.wait_before_destroying_network]
}

# Ensure network creation is fully propagated before attempting certain destruction operations
resource "time_sleep" "wait_before_destroying_network" {
  depends_on       = [google_compute_network.main]
  destroy_duration = "60s"        # Wait 60 seconds after deletion (safety buffer)
}

# ---------------------------------------------------------------------------------
# Resource: Redis instance in Memorystore
resource "google_redis_instance" "main" {
  authorized_network      = google_compute_network.main.name
  connect_mode            = "DIRECT_PEERING"   # Use direct VPC peering
  location_id             = var.zone           # Zone for Redis instance
  memory_size_gb          = 1                  # 1 GB cache
  name                    = "${var.deployment_name}-cache"
  display_name            = "${var.deployment_name}-cache"
  project                 = var.project_id
  redis_version           = "REDIS_6_X"
  region                  = var.region
  reserved_ip_range       = "10.137.125.88/29"  # Pre-allocated IP range for Redis
  tier                    = "BASIC"
  transit_encryption_mode = "DISABLED"           # No encryption (for simplicity)
  labels                  = var.labels
}

# ---------------------------------------------------------------------------------
# Resource: Generate a small random ID to suffix the DB instance name (avoids name conflicts)
resource "random_id" "id" {
  byte_length = 2
}

# ---------------------------------------------------------------------------------
# Resource: Cloud SQL (MySQL or PostgreSQL) instance
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
      ipv4_enabled    = false   # Disable public IP
      private_network = "projects/${var.project_id}/global/networks/${google_compute_network.main.name}"
    }

    location_preference {
      zone = var.zone
    }

    dynamic "database_flags" {
      # If using PostgreSQL, enable IAM authentication
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

# ---------------------------------------------------------------------------------
# Resource: Cloud SQL user configuration
resource "google_sql_user" "main" {
  project        = var.project_id
  instance       = google_sql_database_instance.main.name
  deletion_policy = "ABANDON"   # Keep or drop user on instance deletion?

  name = var.database_type == "postgresql" 
    ? "${google_service_account.runsa.account_id}@${var.project_id}.iam"  # Use service account email for IAM DB auth
    : "foo"    # For MySQL, use a simple user name "foo"

  type = var.database_type == "postgresql" ? "CLOUD_IAM_SERVICE_ACCOUNT" : null
  password = var.database_type == "mysql" 
    ? data.google_secret_manager_secret_version.db_password.secret_data 
    : null
}

# ---------------------------------------------------------------------------------
# Resource: Create a Cloud SQL database inside the instance
resource "google_sql_database" "database" {
  project         = var.project_id
  name            = "todo"
  instance        = google_sql_database_instance.main.name
  deletion_policy = "ABANDON"
}

# ---------------------------------------------------------------------------------
# Resource: Cloud Run service for the API/backend
resource "google_cloud_run_service" "api" {
  name     = "${var.deployment_name}-api"
  provider = google-beta
  location = var.region
  project  = var.project_id

  template {
    spec {
      service_account_name = google_service_account.runsa.email
      containers {
        image = local.api_image   # Use the appropriate API container image

        # Set environment variables for the container based on DB type
        dynamic "env" {
          for_each = var.database_type == "postgresql" 
            ? local.api_env_vars_postgresql 
            : local.api_env_vars_mysql
          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }
    metadata {
      annotations = {
        # Autoscaling: allow up to 8 instances
        "autoscaling.knative.dev/maxScale"         = "8"
        # Grant Cloud Run permission to connect to Cloud SQL
        "run.googleapis.com/cloudsql-instances"    = google_sql_database_instance.main.connection_name
        "run.googleapis.com/client-name"           = "terraform"
        # VPC networking: egress all traffic through VPC connector
        "run.googleapis.com/vpc-access-egress"     = "all"
        "run.googleapis.com/vpc-access-connector"  = google_vpc_access_connector.main.id
      }
      labels = {
        "run.googleapis.com/startupProbeType" = "Default"
      }
    }
  }

  metadata {
    labels = var.labels  # Apply the user-defined labels to Cloud Run service
  }

  autogenerate_revision_name = true   # Let Cloud Run assign a revision name
  depends_on                 = [google_sql_user.main, google_sql_database.database]
  # Ensure DB user and database exist before deploying the service
}

# ---------------------------------------------------------------------------------
# Resource: Cloud Run service for the Frontend (FE)
resource "google_cloud_run_service" "fe" {
  name     = "${var.deployment_name}-fe"
  location = var.region
  project  = var.project_id

  template {
    spec {
      service_account_name = google_service_account.runsa.email
      containers {
        image = local.fe_image   # Frontend container image
        ports {
          container_port = 80   # FE listens on port 80
        }
        env {
          name  = "ENDPOINT"
          value = google_cloud_run_service.api.status[0].url
          # FE gets the URL of the API service to call for backend
        }
      }
    }
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale" = "8"  # Max autoscale instances
      }
      labels = {
        "run.googleapis.com/startupProbeType" = "Default"
      }
    }
  }

  metadata {
    labels = var.labels  # Apply labels to FE service
  }
}

# ---------------------------------------------------------------------------------
# Allow unauthenticated (public) access to the API Cloud Run service
resource "google_cloud_run_service_iam_member" "noauth_api" {
  location = google_cloud_run_service.api.location
  project  = google_cloud_run_service.api.project
  service  = google_cloud_run_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"   # "allUsers" means anyone can invoke (public)
}

# Allow unauthenticated (public) access to the Frontend Cloud Run service
resource "google_cloud_run_service_iam_member" "noauth_fe" {
  location = google_cloud_run_service.fe.location
  project  = google_cloud_run_service.fe.project
  service  = google_cloud_run_service.fe.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
