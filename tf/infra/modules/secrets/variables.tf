variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "github_org" {
  description = "GitHub org whose members can log in to Grafana. Its teams decide the role."
  type        = string
}

variable "grafana_github_client_id" {
  description = "Client ID of the Grafana OAuth App in GitHub"
  type        = string
}

variable "grafana_github_client_secret" {
  description = "Client secret of the Grafana OAuth App in GitHub"
  type        = string
  sensitive   = true
}

variable "alert_email_password" {
  description = "Gmail app password Alertmanager uses to send alert emails"
  type        = string
  sensitive   = true
}
