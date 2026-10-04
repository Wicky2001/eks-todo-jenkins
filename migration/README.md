# PostgreSQL migrations

This folder holds a simple migration runner and the migration files for the todo database.

Each migration is a `.js` file in `migrations/` that exports `up(client)` and `down(client)`. They run in file name order, each inside its own transaction, and the names of the ones already applied are stored in a `migrations` table.

## Run locally

1. Start the local database: `docker compose up -d db` from the repo root.
2. Copy `.env.example` to `.env` in this folder.
3. Run the migrations:

```bash
npm run migrate --workspace migration
```

To revert everything: `npm run migrate --workspace migration -- down`

## In the cluster

The same image runs as the `migrate-db` Job. It has no password: it logs in to RDS with a short-lived token signed by the `backend-sa` ServiceAccount's IAM role (EKS Pod Identity).

initial build
