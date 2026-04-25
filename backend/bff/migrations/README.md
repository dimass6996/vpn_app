# Migrations

Planned migration tool: Alembic.

## Commands

Create or upgrade the local schema:

```bash
alembic upgrade head
```

Create a new revision after model changes:

```bash
alembic revision --autogenerate -m "describe change"
```
