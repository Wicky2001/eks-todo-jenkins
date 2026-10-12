output "grafana_es_password" {
  description = "Password of the read-only Elasticsearch user 'grafana-user', handed to the monitoring module"
  value       = random_password.grafana_user.result
  sensitive   = true
}
