# Dokploy Deployment Guide

Dokploy is a free, self-hostable Platform as a Service (PaaS) that simplifies the deployment of applications and databases.

## Quick Start

### 1. Deploy Dokploy

```bash
./deploy-dokploy.sh
```

This script will:
- Create .env from example if needed
- Ask for custom port (default: 3000)
- Set up required directories
- Check for port conflicts
- Start all services
- Wait for Dokploy to be ready

### 2. Access Dokploy

Once deployed, access Dokploy at:
- **URL**: http://localhost:3000 (or your configured port)
- **First time**: You'll be redirected to `/register` to create admin account

## Architecture

Dokploy runs with the following services:

```yaml
Services:
  - dokploy:      Main application (port 3000 or custom)
  - postgres:     Database backend
  - redis:        Cache and queue backend
  - traefik:      Reverse proxy (ports 80/443)
```

## Configuration

### Environment Variables

Minimal environment variables needed in `.env`:

```bash
ADVERTISE_ADDR=127.0.0.1 # Server IP address (use public IP for cloud deployments)

# Optional: Custom domain (if not using localhost)
DOKPLOY_DOMAIN=deploy.example.com
```

### Ports Used

- **Dokploy UI**: Accessed through Traefik (no direct port exposure)
- **HTTP**: Port 80 (Traefik)
- **HTTPS**: Port 443 (Traefik)

## Deploying Applications

### 1. Create a Project in Dokploy UI

1. Login to Dokploy
2. Click "Create Project"
3. Choose deployment method:
   - Git (GitHub, GitLab, etc.)
   - Docker Image
   - Docker Compose

### 2. Configure Your Application

For Docker Compose applications, ensure your `docker-compose.yml`:

```yaml
services:
  your-app:
    # ... your config ...
    networks:
      - dokploy-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.your-app.rule=Host(`your-domain.com`)"
      - "traefik.http.routers.your-app.entrypoints=websecure"
      - "traefik.http.routers.your-app.tls.certResolver=letsencrypt"

networks:
  dokploy-network:
    external: true
```

### 3. Environment Variables

Set environment variables in Dokploy UI:
- Go to your project
- Click "Environment"
- Add your variables
- Dokploy creates `.env` file automatically

## Maintenance

### Update Dokploy

```bash
docker compose pull
docker compose up -d
```

### Backup Data

Docker volumes contain all data:
- `dokploy_postgres-data`: Database
- `dokploy_redis-data`: Cache
- `dokploy_dokploy-docker-config`: Docker configs

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker logs dokploy -f
```

### Cleanup

To completely remove Dokploy:

```bash
./cleanup-dokploy.sh
```

This will:
- Stop all containers
- Remove volumes (data loss!)
- Remove network
- Clean system directories
- Optionally remove images

## Troubleshooting

### Port Conflicts

If ports 80/443 are in use:
1. Stop conflicting services, or
2. Modify `docker-compose.yml` to use different ports

### Cannot Access Dokploy

1. Check services are running:
   ```bash
   docker compose ps
   ```

2. Check logs for errors:
   ```bash
   docker logs dokploy
   ```

3. Verify port is accessible:
   ```bash
   curl http://localhost:3000
   ```

### Reset Admin Password

1. Access PostgreSQL:
   ```bash
   docker exec -it dokploy-postgres psql -U dokploy
   ```

2. Update admin password in database

## Advanced Configuration

### Custom Domain

1. Point domain to server IP
2. Traefik will handle SSL automatically
3. Configure in Dokploy UI project settings

### External Database

Modify `docker-compose.yml` to use external PostgreSQL:
1. Remove postgres service
2. Update Dokploy environment with external DB URL

### Resource Limits

Add to service definitions in `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      cpus: '2'
      memory: 2G
```

## Security Considerations

1. **Change default passwords** immediately after setup
2. **Use HTTPS** for production deployments
3. **Firewall**: Only expose necessary ports
4. **Updates**: Keep Dokploy and dependencies updated
5. **Backups**: Regular backup of volumes

## Support

- Documentation: https://docs.dokploy.com
- GitHub: https://github.com/dokploy/dokploy
- Community: Check GitHub discussions