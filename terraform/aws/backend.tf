terraform {
  backend "s3" {
    bucket         = "fleetman-eks-tfstate-659468809437"
    key            = "fleetman-eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "fleetman-eks-tfstate-lock"
    encrypt        = true
  }
}