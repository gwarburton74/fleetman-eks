terraform {
    required_version = "> 1.0"

    required_providers {
      google = {
        source = "hashicorp/google"
        version = ">= 7.17.0, < 8.0.0"
      }
    }
}

provider "google" {
  project = var.gcp_project_id
  region = var.gcp_region
}