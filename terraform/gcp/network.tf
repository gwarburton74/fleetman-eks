module "vpc" {
  source = "terraform-google-modules/network/google"
  version = "~> 18.0"

  project_id = var.gcp_project_id
  network_name = "${var.cluster_name}-vpc"

  subnets = [
    {
        subnet_name           = "${var.cluster_name}-subnet"
        subnet_ip             = "10.0.0.0/20"
        subnet_region         = var.gcp_region
        subnet_private_access = "true"
    }
  ]

  secondary_ranges = {
    "${var.cluster_name}-subnet" = [
        {
            range_name = "pods"
            ip_cidr_range = "10.4.0.0/14"
        },
        {
            range_name = "services"
            ip_cidr_range = "10.8.0.0/20"
        }
    ]
  }
}