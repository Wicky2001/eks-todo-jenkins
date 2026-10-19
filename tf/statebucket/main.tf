###############################################################################
# AWS provider
###############################################################################
# Same account and profile as tf/infra.
provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

###############################################################################
# Terraform settings
###############################################################################
# No backend here: this state stays local, because this creates the bucket the
# other state goes in.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

###############################################################################
# Current AWS account
###############################################################################
# Account ID, used in the bucket name.
data "aws_caller_identity" "current" {}

###############################################################################
# State bucket
###############################################################################
# Holds the Terraform state of tf/infra. Versioning keeps old copies of the state.
resource "aws_s3_bucket" "state" {
  bucket        = "todo-cluster-terraform-state-677501681528"
  force_destroy = true

}

###############################################################################
# Bucket versioning
###############################################################################
# Keeps old copies of the state file.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}
