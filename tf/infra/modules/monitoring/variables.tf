variable "grafana_es_password" {
  description = "Password of the read-only Elasticsearch user 'grafana-user' (from the logging module)"
  type        = string
  sensitive   = true
}
