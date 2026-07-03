###############################################################################
# Environment
###############################################################################
variable "region" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "aws_profile" {
  type = string
}

###############################################################################
# Cluster
###############################################################################
variable "cluster_name" {
  type = string
}

variable "project_name" {
  type = string
}

variable "master_username" {
  type = string
}

variable "master_password" {
  type = string
}
