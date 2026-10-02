variable "cluster_name" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "node_security_group_id" {
  type = string
}

variable "app_namespace" {
  type = string
}

variable "db_name" {
  type    = string
  default = "todos"
}

variable "db_username" {
  type    = string
  default = "todo_app"
}

variable "service_account_name" {
  type    = string
  default = "backend-sa"
}
