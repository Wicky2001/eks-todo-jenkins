# Local PostgreSQL

This folder contains the Docker Compose setup for the local PostgreSQL database used by the todo app.

If you prefer the single-container command, use:

```bash
docker run -dt -p 5432:5432 --name todo-db -e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=todos postgres:17-alpine
```

The backend and the migration read `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` and `DB_PASSWORD`. See `backend/.env.example` and `migration/.env.example` for the local values.
