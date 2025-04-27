terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "<= 4.74, != 4.75.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "<= 4.74, != 4.75.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 2.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  provider_meta "google" {
    module_name = "blueprints/terraform/terraform-google-three-tier-web-app/v0.1.9"
  }
}

