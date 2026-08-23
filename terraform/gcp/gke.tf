module "gke" {
  source = "terraform-google-modules/kubernetes-engine/google"
  version = "~> 9.0"

  project_id = var.gcp_project_id
  name = var.cluster_name
  region = var.gcp_region
  regional = true

  network = module.vpc.network_name
  subnetwork = "${var.cluster_name}-subnet"

  ip_range_pods = "pods"
  ip_range_services = "services"

  node_pools = [
    {
        name = "default"
        machine-type = "e2-medium"
        min_count = 1
        max_count = 3
    }
  ]
}