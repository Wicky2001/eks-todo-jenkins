# EKS Todo

Monorepo scaffold for a simple todo app built with React, Express.js, and PostgreSQL (Amazon RDS in the cluster, a local container on your machine).

## Structure

- `frontend` - React UI
- `backend` - Express MVC API
- `developmentTools/db` - local PostgreSQL Docker Compose setup
- `migration` - migration scripts and runner
- `scripts` - one-off helper scripts (for example, creating the database login user)
- `tf` - Terraform for the AWS infrastructure
- `k8s` - Kubernetes manifests

## Local setup

1. Install dependencies from the repo root.
2. Copy each `.env.example` file to `.env` in the matching folder (`backend`, `migration`).
3. Start PostgreSQL with Docker Compose from `developmentTools/db`.
4. Run the migrations: `npm run migrate`.
5. Start the backend and frontend workspaces.

Or run everything in containers with `docker compose up --build` from the repo root.

## Database in the cluster

The backend and the migration job log in to Amazon RDS **without a password**. They run as the `backend-sa` ServiceAccount, which EKS Pod Identity links to an IAM role. The role may only call `rds-db:connect` for one database user, so only pods running as `backend-sa` can get a login token. After the first `terraform apply`, run `scripts/init-db-user.sh` once to create that database user.

## Documentation

Read these in order if you have forgotten how the AWS permissions work:

1. [EKS Pod Identity (and why we do not use IRSA)](tf/infra/modules/eks/README.md): how a pod gets AWS permissions, what EKS injects, and where each piece lives.
2. [How the backend logs in to RDS with IAM](tf/infra/modules/rds/README.md): the badge, keys and login note, the Signer, TLS, the init script and troubleshooting.

## Notes for K8s practice

This scaffold keeps the app split into separate frontend, backend, database tooling, and migration areas so it can later be mapped into Kubernetes Deployments, Services, and ConfigMaps without restructuring the codebase.
