###############################################################################
# Provider
###############################################################################
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

###############################################################################
# S3 Bucket
###############################################################################
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
