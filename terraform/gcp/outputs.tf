output "cluster_name" {
  description = "GKE cluster name"
  value = module.gke.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value = module.gke.endpoint
  sensitive = true
}

output "cluster_region" {
  description = "GCP region"
  value = var.gcp_region
}

output "github_actions_service_account" {
  description = "Service account email GitHub Actions impersonates via Workload Identity Federation"
  value = google_service_account.github_actions.email
}