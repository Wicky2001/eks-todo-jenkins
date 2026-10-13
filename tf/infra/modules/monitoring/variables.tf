variable "grafana_es_password" {
  description = "Password of the read-only Elasticsearch user 'grafana-user' (from the logging module)"
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "GitHub org whose members can log in to Grafana. Its teams decide the role."
  type        = string
}

variable "github_client_id" {
  description = "Client ID of the Grafana OAuth App in GitHub"
  type        = string
}

variable "github_client_secret" {
  description = "Client secret of the Grafana OAuth App in GitHub"
  type        = string
  sensitive   = true
}
