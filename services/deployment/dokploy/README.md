# Dokploy - Open Source Deployment Platform

Dokploy is an open-source alternative to Vercel/Netlify/Heroku for deploying applications.

## Features

- Deploy applications from GitHub
- Automatic SSL certificates
- Database management (PostgreSQL, MySQL, MongoDB)
- Redis support
- Environment variables management
- Custom domains
- Webhook deployments
- Docker-based deployments

## Quick Start

1. Copy environment file:
   ```bash
   cp .env.example .env
   ```

2. Generate a secret key:
   ```bash
   openssl rand -hex 32
   ```
   Add this to SECRET_KEY in .env

3. Update passwords and configuration in `.env`

4. Start Dokploy:
   ```bash
   docker compose up -d
   ```

5. Access Dokploy at `http://localhost:3000`

## Initial Setup

1. Navigate to the web interface
2. Create your admin account using the credentials from .env
3. Configure your domains and SSL settings
4. Connect your GitHub account (optional)

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| SECRET_KEY | Encryption key (min 32 chars) | Yes |
| ADMIN_EMAIL | Admin email address | Yes |
| ADMIN_PASSWORD | Admin password | Yes |
| WEBHOOK_SECRET | Secret for webhook validation | Yes |
| BASE_URL | Public URL of Dokploy | Yes |
| POSTGRES_PASSWORD | Database password | Yes |

## GitHub Integration

To enable GitHub deployments:

1. Create a GitHub App
2. Add the App ID and Private Key to .env
3. Configure OAuth with Client ID and Secret

## Backup

Dokploy data is stored in:
- `dokploy_data`: Application data and SQLite database
- `postgres_data`: PostgreSQL data (if using external apps)
- `./backups`: Backup directory

To backup:
```bash
docker compose exec dokploy dokploy backup
```

## Security Notes

- Change all default passwords
- Use a strong SECRET_KEY
- Configure firewall rules
- Enable SSL for production
- Regularly update the Docker image

## Troubleshooting

- Check logs: `docker compose logs dokploy`
- Ensure Docker socket is accessible
- Verify all required environment variables are set
- Check that ports are not already in use