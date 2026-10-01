###############################################################################
# ecr repository for custom app images
###############################################################################

resource "aws_ecr_repository" "frontend" {
  name         = "${var.project_name}-frontend"
  force_delete = true
}

resource "aws_ecr_repository" "backend" {
  name         = "${var.project_name}-backend"
  force_delete = true
}

resource "aws_ecr_repository" "migration" {
  name         = "${var.project_name}-migration"
  force_delete = true
}

# Every commit pushes a new image, so keep only the latest 10 per repo
# to stop ECR storage costs from growing forever.
resource "aws_ecr_lifecycle_policy" "keep_last_10" {
  for_each = {
    frontend  = aws_ecr_repository.frontend.name
    backend   = aws_ecr_repository.backend.name
    migration = aws_ecr_repository.migration.name
  }

  repository = each.value

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}


###############################################################################
# IAM user for Jenkins to push images to ECR
###############################################################################

/*
  Jenkins runs outside AWS, so it needs access keys.
  The access key itself is NOT created here (it would end up in the
  Terraform state in plain text). Create it in the console instead:
  IAM -> Users -> <this user> -> Security credentials -> Create access key
*/
resource "aws_iam_user" "jenkins" {
  name = "${var.project_name}-jenkins"
}

resource "aws_iam_user_policy" "jenkins_ecr_push" {
  name = "ecr-push"
  user = aws_iam_user.jenkins.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Needed for 'docker login'. This action can't be scoped to a repo.
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        # Push only to this project's 3 repositories.
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage"
        ]
        Resource = [
          aws_ecr_repository.frontend.arn,
          aws_ecr_repository.backend.arn,
          aws_ecr_repository.migration.arn
        ]
      }
    ]
  })
}
