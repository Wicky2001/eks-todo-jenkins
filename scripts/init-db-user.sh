#!/usr/bin/env bash
#
# Run this ONCE, after the first `terraform apply` finished and kubectl works
# (aws eks update-kubeconfig --region <region> --name todo-cluster).
#
# Why it is needed: Terraform creates the RDS server, but a database user is something
# you create INSIDE the database, and the database is in a private subnet that your laptop
# cannot reach. So this script starts a short-lived psql pod in the cluster, logs in as the
# RDS admin (password read from AWS Secrets Manager) and creates the passwordless user
# that the backend logs in as with its IAM token.
#
# Safe to run again: every step can be repeated.

set -euo pipefail

export AWS_PROFILE="${AWS_PROFILE:-terraform-user}"

cd "$(dirname "$0")/../tf/infra"

HOST="$(terraform output -raw db_endpoint)"
DB_NAME="$(terraform output -raw db_name)"
DB_USER="$(terraform output -raw db_user)"
MASTER_USER="$(terraform output -raw db_master_username)"
SECRET_ARN="$(terraform output -raw db_master_secret_arn)"

# arn:aws:secretsmanager:<region>:<account>:secret:<name>  ->  <region>
REGION="$(echo "${SECRET_ARN}" | cut -d: -f4)"

PASSWORD="$(aws secretsmanager get-secret-value \
  --secret-id "${SECRET_ARN}" \
  --region "${REGION}" \
  --query SecretString \
  --output text | node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(0, "utf8")).password)')"

# rds_iam is the RDS role that means "this user logs in with an IAM token, not a password".
SQL="
CREATE ROLE ${DB_USER} WITH LOGIN;
GRANT rds_iam TO ${DB_USER};
GRANT ALL ON SCHEMA public TO ${DB_USER};
"

echo "Creating database user '${DB_USER}' on ${HOST} ..."

kubectl run db-init -n app --rm -i --restart=Never --image=postgres:17-alpine \
  --env="PGPASSWORD=${PASSWORD}" -- \
  psql "host=${HOST} port=5432 dbname=${DB_NAME} user=${MASTER_USER} sslmode=require" \
  -v ON_ERROR_STOP=1 -c "${SQL}"

echo "Done. '${DB_USER}' can now log in with an IAM token. Run the migration next (Argo CD does this on its first sync)."
