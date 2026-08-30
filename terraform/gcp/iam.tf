resource "google_iam_workload_identity_pool" "github" {
  project                   = var.gcp_project_id
  workload_identity_pool_id = "github-pool-v2"
  display_name              = "GitHub Actions Pool"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project = var.gcp_project_id
  workload_identity_pool_id = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name = "GitHub Actions Provider"

  attribute_condition = "assertion.repository == '${var.github_username}/${var.github_repo}'"
  
  attribute_mapping = {
    "google.subject" = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_actions" {
  project = var.gcp_project_id
  account_id = "github-actions-deploy"
  display_name = "GitHub Actions Deploy"
}

resource "google_service_account_iam_member" "github_impersonation" {
  service_account_id = google_service_account.github_actions.name
  role = "roles/iam.workloadIdentityUser"
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_username}/${var.github_repo}"
}

resource "google_project_iam_member" "github_actions_editor" {
  project = var.gcp_project_id
  role = "roles/editor"
  member = "serviceAccount:${google_service_account.github_actions.email}"
}