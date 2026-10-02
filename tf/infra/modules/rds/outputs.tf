output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_name" {
  value = var.db_name
}

output "db_user" {
  value = var.db_username
}

output "db_master_username" {
  value = aws_db_instance.this.username
}

output "db_master_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "backend_role_arn" {
  value = module.backend_pod_identity.iam_role_arn
}
