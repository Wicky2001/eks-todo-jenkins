output "frontend_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "backend_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "migration_repository_url" {
  value = aws_ecr_repository.migration.repository_url
}

output "jenkins_iam_user_name" {
  value = aws_iam_user.jenkins.name
}
