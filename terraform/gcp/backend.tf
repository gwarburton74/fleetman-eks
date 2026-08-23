terraform {
    backend "gcs" {
        bucket = "fleetman-eks-tfstate-431880270172"
        prefix = "fleetman-eks/terraform.tfstate"
    }
}