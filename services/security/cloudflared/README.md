# Cloudflare Tunnel (cloudflared)

Securely expose your local services to the internet using Cloudflare Tunnel.

## Features

- Zero-trust security model
- No exposed ports or public IPs
- Built-in DDoS protection
- Automatic SSL/TLS certificates
- Load balancing and failover
- Access policies and authentication
- WebSocket and TCP support

## Prerequisites

- Cloudflare account (free tier works)
- Domain added to Cloudflare
- Access to Cloudflare dashboard

## Quick Start (Token Method - Recommended)

### 1. Create a Tunnel in Cloudflare Dashboard

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to Access → Tunnels
3. Click "Create a tunnel"
4. Name your tunnel and save
5. Copy the tunnel token

### 2. Configure and Run

```bash
# Copy environment file
cp .env.example .env

# Add your tunnel token to .env
# TUNNEL_TOKEN=your-tunnel-token-here

# Start the tunnel
docker compose up -d
```

## Advanced Setup (Config File Method)

### 1. Initial Setup

```bash
# Run the management container to set up credentials
docker compose --profile setup run cloudflared-management
```

This will:
- Open a browser for Cloudflare login
- Create tunnel credentials
- Save credentials to `./creds/`

### 2. Configure Tunnel

Edit `config/config.yml` with your services:

```yaml
ingress:
  - hostname: app.yourdomain.com
    service: http://your-app:3000
  - hostname: api.yourdomain.com
    service: http://your-api:8000
  - service: http_status:404
```

### 3. Run with Config

```bash
docker compose --profile config up -d
```

## Configuration Examples

### Basic Web Service

```yaml
- hostname: myapp.example.com
  service: http://myapp:8080
```

### With Custom Headers

```yaml
- hostname: api.example.com
  service: http://api:3000
  originRequest:
    httpHostHeader: api.internal
    noTLSVerify: false
```

### WebSocket Support

```yaml
- hostname: ws.example.com
  service: ws://websocket-server:9000
```

### TCP Services (SSH, Database)

```yaml
- hostname: ssh.example.com
  service: tcp://ssh-server:22
```

### Path-based Routing

```yaml
- hostname: example.com
  path: /api/*
  service: http://api:8000
- hostname: example.com
  path: /*
  service: http://frontend:3000
```

## Connecting Services

### Option 1: Same Docker Network

Add your service to the cloudflared network:

```yaml
services:
  myapp:
    image: myapp:latest
    networks:
      - cloudflared_network
```

### Option 2: External Network

```bash
# Create network
docker network create tunnel_network

# Connect your app
docker network connect tunnel_network myapp

# Update config.yml to use container names
```

## Access Policies

Configure access policies in Cloudflare Dashboard:

1. Go to Access → Applications
2. Create application
3. Set policy rules:
   - Email authentication
   - IP restrictions
   - Device certificates
   - Multi-factor authentication

## Monitoring

### View Tunnel Status

```bash
# Check logs
docker compose logs cloudflared

# View metrics (if enabled)
curl http://localhost:2000/metrics
```

### Cloudflare Dashboard

- Real-time analytics
- Request logs
- Error tracking
- Performance metrics

## Multiple Tunnels

Run multiple tunnels for different environments:

```bash
# Production tunnel
TUNNEL_TOKEN=prod-token docker compose -p prod up -d

# Staging tunnel
TUNNEL_TOKEN=staging-token docker compose -p staging up -d
```

## Security Best Practices

1. **Use Access Policies** - Require authentication for sensitive services
2. **Enable Bot Fight Mode** - Block automated attacks
3. **Configure Rate Limiting** - Prevent abuse
4. **Use Service Tokens** - For API authentication
5. **Regular Token Rotation** - Rotate tunnel tokens periodically
6. **Monitor Access Logs** - Track who accesses your services

## Troubleshooting

### Connection Issues

```bash
# Check tunnel status
docker compose logs cloudflared | grep "Connection"

# Verify DNS records
nslookup your-tunnel.example.com

# Test connectivity
curl -I https://your-tunnel.example.com
```

### Common Problems

1. **"No connection to edge"** - Check internet connectivity
2. **"Unauthorized"** - Verify tunnel token
3. **"502 Bad Gateway"** - Check if backend service is running
4. **"Certificate error"** - Update cloudflared image

## Load Balancing

For high availability, run multiple tunnel instances:

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    deploy:
      replicas: 3
    # ... rest of config
```

## Integration with Other Services

### Traefik

```yaml
# In Traefik labels
- "traefik.http.routers.myapp.rule=Host(`myapp.local`)"
# Then point cloudflared to http://traefik
```

### Nginx Proxy Manager

Point cloudflared to your Nginx Proxy Manager instance for additional routing options.

## Backup Tunnel Credentials

```bash
# Backup credentials
tar -czf tunnel-creds-backup.tar.gz ./creds/

# Restore
tar -xzf tunnel-creds-backup.tar.gz
```