variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "EKS Cluster name"
  type        = string
  default     = "eks-sockshop-cluster"
}

variable "github_owner" {
  description = "GitHub username or organization name"
  type        = string
}

variable "github_repo_name" {
  description = "Name of the GitHub repository"
  type        = string
}

variable "github_branch" {
  description = "The branch to use for the GitHub repository"
  type        = string
  # You can specify your default branch or leave it empty to make it a required input
}

variable "github_repo_url" {
  description = "HTTPS URL of the GitHub repository"
  type        = string
}
variable "github_token" {
  description = "GitHub OAuth token"
  type        = string
  sensitive   = true
}
