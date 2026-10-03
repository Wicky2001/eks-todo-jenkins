###############################################################################
# PostgreSQL on Amazon RDS
###############################################################################

data "aws_caller_identity" "current" {}

# RDS needs subnets in at least two Availability Zones. We use the private ones,
# so the database has no route from the internet.
resource "aws_db_subnet_group" "this" {
  name       = "${var.cluster_name}-postgres"
  subnet_ids = var.private_subnets
}

# Network lock: only the EKS worker nodes (where all pods run) can reach port 5432.
resource "aws_security_group" "rds" {
  name        = "${var.cluster_name}-postgres"
  description = "PostgreSQL access from the EKS worker nodes only"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "from_nodes" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = var.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from the EKS worker nodes"
}

resource "aws_db_instance" "this" {
  identifier     = "${var.cluster_name}-postgres"
  engine         = "postgres"
  engine_version = "17"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = "dbadmin"

  # RDS creates the admin password itself and keeps it in AWS Secrets Manager,
  # so it never appears in Terraform code or state.
  manage_master_user_password = true

  # Identity lock: users that have the rds_iam role log in with a short-lived
  # IAM token instead of a password.
  iam_database_authentication_enabled = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  apply_immediately          = true

  # Learning setup: destroying the stack deletes the database without a final snapshot.
  skip_final_snapshot = true
  deletion_protection = false
}

###############################################################################
# IAM role for the backend pod (EKS Pod Identity)
###############################################################################

# The role can do exactly one thing: ask for a login token for the "todo_app_db_user"
# database user on this one database server. Pod Identity gives the role only to pods
# that run as the backend ServiceAccount in the app namespace.
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
# Connection settings for the pods (the database address is only known after RDS exists)
###############################################################################
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
