# PostgreSQL with PgAdmin

Production-ready PostgreSQL database with PgAdmin web interface.

## Features

- PostgreSQL 16 Alpine (lightweight)
- PgAdmin 4 for web-based management
- Health checks for reliability
- Volume persistence for data
- Network isolation
- Log rotation configured

## Quick Start

1. Copy environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your values (especially passwords!)

3. Start services:
   ```bash
   docker compose up -d
   ```

4. Access:
   - PostgreSQL: `localhost:5432` (or your configured port)
   - PgAdmin: `http://localhost:5050`

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| POSTGRES_DB | myapp | Database name |
| POSTGRES_USER | postgres | Database user |
| POSTGRES_PASSWORD | (required) | Database password |
| POSTGRES_PORT | 5432 | PostgreSQL port |
| PGADMIN_EMAIL | admin@example.com | PgAdmin login email |
| PGADMIN_PASSWORD | (required) | PgAdmin password |
| PGADMIN_PORT | 5050 | PgAdmin web port |

## Adding PgAdmin Server

1. Login to PgAdmin
2. Right-click "Servers" → "Create" → "Server"
3. General tab: Name = `postgres`
4. Connection tab:
   - Host: `postgres` (service name)
   - Port: `5432`
   - Username: Value from POSTGRES_USER
   - Password: Value from POSTGRES_PASSWORD

## Initialization Scripts

Place `.sql` or `.sh` files in `./init/` directory. They will run on first startup.

## Backup

```bash
# Backup
docker exec postgres pg_dump -U postgres myapp > backup.sql

# Restore
docker exec -i postgres psql -U postgres myapp < backup.sql
```

## Security Notes

- Change all default passwords
- Consider using Docker secrets for production
- Restrict network access as needed
- Enable SSL for external connections