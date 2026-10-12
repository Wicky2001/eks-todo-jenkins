provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

data "aws_caller_identity" "current" {}

# Holds the Terraform state of tf/infra. Versioning keeps old copies of the state.
resource "aws_s3_bucket" "state" {
  bucket        = "todo-cluster-terraform-state-677501681528"
  force_destroy = true

}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}
