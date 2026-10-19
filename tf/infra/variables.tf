# Environment
variable "region" {
  type = string
}

variable "aws_profile" {
  type    = string
  default = "terraform-user"
}

# Cluster
variable "cluster_name" {
  type = string
}

variable "project_name" {
  type = string
}

# HTTPS
variable "letsencrypt_email" {
  type = string
}

# GitHub login for Argo CD and Grafana (one OAuth App each, owned by the GitHub org)
variable "github_org" {
  type = string
}

variable "argocd_github_client_id" {
  type = string
}

variable "argocd_github_client_secret" {
  type      = string
  sensitive = true
}

variable "grafana_github_client_id" {
  type = string
}

variable "grafana_github_client_secret" {
  type      = string
  sensitive = true
}

# Alert emails (Alertmanager)
variable "alert_email_password" {
  description = "Gmail app password Alertmanager uses to send alert emails"
  type        = string
  sensitive   = true
}
