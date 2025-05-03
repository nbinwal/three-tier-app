terraform {
  required_version = ">= 1.5.0"
  # Specifies the minimum Terraform version required

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.0.0, <= 4.74.0, != 4.75.0"
      # Use Google provider v4 up to 4.74 (avoid 4.75.0)
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 4.0.0, <= 4.74.0, != 4.75.0"
      # Google Beta provider for services in beta (similar version constraint)
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 2.2.0"
      # Used for generating random identifiers
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12.0"
      # Used for sleep/waiting operations
    }
  }
}

provider_meta "google" {
  module_name = "blueprints/terraform/terraform-google-three-tier-web-app/v0.1.9"
  # Metadata tag linking this config to the "three-tier-web-app" blueprint version
}
