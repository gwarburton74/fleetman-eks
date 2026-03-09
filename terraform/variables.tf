variable "aws_region" {
  description = "AWS region to deploy into"
  type = string
  default = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type = string
  default = "fleetman-eks"
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