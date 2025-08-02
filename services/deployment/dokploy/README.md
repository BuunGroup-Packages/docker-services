# Dokploy - Self-Hosted PaaS

Dokploy is a free, self-hostable Platform as a Service (PaaS) that simplifies application deployment using Docker.

## Features

- 🚀 Deploy applications from Git, Docker images, or Docker Compose
- 🔧 Built-in database support (PostgreSQL, MySQL, MongoDB, Redis)
- 🔒 Automatic SSL with Let's Encrypt via Traefik
- 🌐 Multi-domain support
- 📊 Real-time logs and monitoring
- 🔄 Zero-downtime deployments
- 🎯 Simple UI for managing deployments

## Quick Start

1. **Deploy Dokploy**:
   ```bash
   ./deploy-dokploy.sh
   ```

2. **Access the UI**:
   - Navigate to http://localhost:3000 (or your configured port)
   - Register your admin account on first visit

3. **Deploy your first app**:
   - Click "Create Project"
   - Choose your deployment method (Git, Docker, Docker Compose)
   - Follow the guided setup

## Scripts

- `deploy-dokploy.sh` - Deploy Dokploy with all services
- `cleanup-dokploy.sh` - Remove Dokploy and all data

## Configuration

Minimal configuration needed in `.env`:
```bash
DOKPLOY_PORT=3000        # UI port (default: 3000)
ADVERTISE_ADDR=127.0.0.1 # Server IP address
```

The deploy script will:
- Create `.env` from example if it doesn't exist
- Ask for custom port during setup
- Check for port conflicts before starting
- Set up all required directories
- Wait for services to be ready

## Architecture

Dokploy runs with four main services:

```
┌─────────────┐     ┌────────────┐     ┌─────────┐
│   Dokploy   │────▶│ PostgreSQL │     │  Redis  │
│     UI      │     └────────────┘     └─────────┘
└──────┬──────┘              
       │                     
       ▼                     
┌─────────────┐     ┌─────────────────────────────┐
│   Traefik   │────▶│     Your Applications       │
│ (80/443)    │     │  (Connected via network)    │
└─────────────┘     └─────────────────────────────┘
```

## Deploying Applications

### Via Dokploy UI

1. Create a new project
2. Configure deployment source:
   - **Git**: Connect GitHub/GitLab repository
   - **Docker Image**: Deploy from Docker Hub
   - **Docker Compose**: Upload compose file

3. Set environment variables
4. Configure domains
5. Deploy!

### Docker Compose Example

For apps deployed via Docker Compose:

```yaml
services:
  your-app:
    image: your-app:latest
    networks:
      - dokploy-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.your-app.rule=Host(`app.yourdomain.com`)"
      - "traefik.http.routers.your-app.entrypoints=websecure"
      - "traefik.http.routers.your-app.tls.certResolver=letsencrypt"

networks:
  dokploy-network:
    external: true
```

## Maintenance

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker logs dokploy -f
```

### Update Dokploy
```bash
docker-compose pull
docker-compose up -d
```

### Backup Data
All data is stored in Docker volumes:
- `dokploy_postgres-data` - Database
- `dokploy_redis-data` - Cache
- `dokploy_dokploy-docker-config` - Docker configs

## Troubleshooting

### Cannot Access Dokploy
1. Check if services are running: `docker-compose ps`
2. Check logs: `docker logs dokploy`
3. Verify port: `curl http://localhost:3000`

### Port Conflicts
- The deploy script checks for conflicts on ports 80, 443, and your chosen Dokploy port
- Stop conflicting services or modify `docker-compose.yml`

### Complete Reset
```bash
./cleanup-dokploy.sh  # Warning: Deletes all data!
./deploy-dokploy.sh   # Fresh install
```

## Documentation

- [Deployment Guide](DEPLOYMENT_GUIDE.md) - Detailed deployment instructions
- [Official Docs](https://docs.dokploy.com) - Complete documentation
- [GitHub](https://github.com/dokploy/dokploy) - Source code and issues

## License

Dokploy is open source software.