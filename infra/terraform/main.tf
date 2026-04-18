# -----------------------------------------------------------------------------
# main.tf – Provider and Terraform settings for CoupleSync infrastructure
# -----------------------------------------------------------------------------
# We use the google-beta provider because several Firebase resources
# (firebase_android_app, firebase_apple_app, etc.) are only available in beta.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"

  required_providers {
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0"
    }
  }
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}
