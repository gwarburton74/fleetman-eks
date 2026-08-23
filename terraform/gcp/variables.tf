variable "gcp_project_id" {
    description = "GCP project ID to deploy into"
    type = string
    default = "project-ddc36e36-dfad-4b07-b65"
}

variable "gcp_region" {
  description = "GCP region to deploy into"
  type = string
  default = "us-central1"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type = string
  default = "fleetman-gke"
}

variable "github_username" {
    description = "GitHub username for OIDC trust"
    type = string
    default = "gwarburton74"
}

variable "github_repo" {
  description = "GitHub repo name for OIDC trust"
  type = string
  default = "fleetman-eks"
}