resource "google_compute_router" "nat_router" {
  name = "${var.cluster_name}-nat-router"
  region = "${var.gcp_region}"
  network = module.vpc.network_self_link
}

resource "google_compute_router_nat" "nat" {
  name = "${var.cluster_name}-nat"
  router = google_compute_router.nat_router.name
  region = "${var.gcp_region}"

  nat_ip_allocate_option = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}