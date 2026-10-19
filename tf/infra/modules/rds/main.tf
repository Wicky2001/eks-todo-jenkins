# PostgreSQL on RDS

###############################################################################
# Current AWS account
###############################################################################
# Account ID, used in the IAM policy below.
data "aws_caller_identity" "current" {}

###############################################################################
# DB subnet group
###############################################################################
# private subnets in two zones, so the database can't be reached from the internet
resource "aws_db_subnet_group" "this" {
  name       = "${var.cluster_name}-postgres"
  subnet_ids = var.private_subnets
}

###############################################################################
# Database security group
###############################################################################
# only the EKS worker nodes can reach port 5432
resource "aws_security_group" "rds" {
  name        = "${var.cluster_name}-postgres"
  description = "PostgreSQL access from the EKS worker nodes only"
  vpc_id      = var.vpc_id
}

###############################################################################
# Allow the nodes
###############################################################################
# Port 5432 from the EKS node security group.
resource "aws_vpc_security_group_ingress_rule" "from_nodes" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = var.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from the EKS worker nodes"
}

###############################################################################
# PostgreSQL database
###############################################################################
# db.t3.micro, single zone, IAM login turned on.
resource "aws_db_instance" "this" {
  identifier     = "${var.cluster_name}-postgres"
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = "dbadmin"

  # RDS generates the admin password and keeps it in Secrets Manager,
  # so it is never in the code or the Terraform state.
  manage_master_user_password = true

  # Users with the rds_iam role log in with a short-lived IAM token instead of a password.
  iam_database_authentication_enabled = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  apply_immediately          = true

  # learning setup: terraform destroy removes the database without a final snapshot
  skip_final_snapshot = true
  deletion_protection = false
}

###############################################################################
# Backend IAM role
###############################################################################
# IAM role for the backend pod (Pod Identity). It can only get a login token for the
# app's database user on this database, and only pods using the backend ServiceAccount get it.
module "backend_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "${var.cluster_name}-backend-iam"

  attach_custom_policy = true
  policy_statements = [
    {
      sid     = "ConnectToTodoDatabaseAsTodoApp"
      actions = ["rds-db:connect"]
      resources = [
        "arn:aws:rds-db:${var.region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_instance.this.resource_id}/${var.db_username}"
      ]
    }
  ]

  associations = {
    this = {
      cluster_name    = var.cluster_name
      namespace       = var.app_namespace
      service_account = var.service_account_name
    }
  }
}

###############################################################################
# Database settings for the pods
###############################################################################
# Database address for the backend and migration pods (only known once RDS exists)
resource "kubernetes_config_map_v1" "backend_db" {
  metadata {
    name      = "backend-db-config"
    namespace = var.app_namespace
  }

  data = {
    DB_HOST    = aws_db_instance.this.address
    DB_PORT    = tostring(aws_db_instance.this.port)
    DB_NAME    = var.db_name
    DB_USER    = var.db_username
    AWS_REGION = var.region
  }
}
