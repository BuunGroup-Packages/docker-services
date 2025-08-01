# Docker Services Repository

Production-ready Docker Compose configurations for rapid application deployment.

## Overview

This repository provides a collection of pre-configured Docker services that can be quickly deployed in production environments. Each service includes:

- Optimized Docker Compose configurations
- Environment variable templates
- Health checks and restart policies
- Volume persistence
- Network isolation
- Logging configuration
- Security best practices

## Quick Start

### 1. Install Docker

Run the bootstrap script to install Docker on your system:

```bash
./bootstrap.sh
```

This script:
- Detects your Linux distribution (Ubuntu, Debian, RHEL, CentOS, Fedora, Rocky, AlmaLinux)
- Installs Docker Engine with Compose plugin
- Sets up user permissions
- Validates the installation

### 2. Deploy a Service

Example: Deploy PostgreSQL with PgAdmin

```bash
cd services/databases/postgres
cp .env.example .env
# Edit .env with your passwords
docker compose up -d
```

## Repository Structure

```
docker-services/
├── bootstrap.sh                # Docker installation script
├── scripts/                    # Utility scripts
│   ├── install-docker.sh       # Distribution-specific installation
│   ├── setup-user.sh           # User permissions setup
│   └── validate-environment.sh # Environment validation
│
├── services/                   # Service configurations
│   ├── databases/              # Database services
│   │   ├── postgres/           # PostgreSQL + PgAdmin
│   │   ├── mysql/              # MySQL + phpMyAdmin
│   │   └── mongodb/            # MongoDB + Mongo Express
│   │
│   ├── cache/                  # Caching services
│   │   ├── redis/              # Redis + RedisInsight
│   │   └── memcached/          # Memcached
│   │
│   ├── web-servers/            # Web servers
│   │   ├── nginx/              # Nginx
│   │   └── apache/             # Apache
│   │
│   ├── reverse-proxy/          # Reverse proxies
│   │   ├── traefik/            # Traefik with auto SSL
│   │   └── nginx-proxy/        # Nginx Proxy Manager
│   │
│   ├── monitoring/             # Monitoring stacks
│   │   ├── prometheus-grafana/ # Prometheus + Grafana
│   │   ├── elk-stack/          # Elasticsearch, Logstash, Kibana
│   │   └── loki-alloy/         # Loki + Alloy
│   │
│   ├── message-brokers/        # Message queues
│   │   ├── rabbitmq/           # RabbitMQ
│   │   └── kafka/              # Apache Kafka
│   │
│   └── full-stacks/            # Complete application stacks
│       ├── wordpress-nginx-redis/
│       ├── django-postgres-redis/
│       └── nextcloud-nginx-redis/
│
└── templates/                  # Reusable templates
```

## Available Services

### Databases
- **PostgreSQL**: With PgAdmin web interface
- **MySQL**: With phpMyAdmin interface
- **MongoDB**: With Mongo Express interface

### Cache Systems
- **Redis**: With RedisInsight management
- **Memcached**: Lightweight caching

### Web Servers
- **Nginx**: High-performance web server
- **Apache**: Feature-rich web server

### Reverse Proxies
- **Traefik**: Modern proxy with auto SSL
- **Nginx Proxy Manager**: GUI-based proxy management

### Monitoring
- **Prometheus + Grafana**: Metrics and visualization
- **ELK Stack**: Log aggregation and analysis
- **Loki + Alloy**: Lightweight log aggregation

### Message Brokers
- **RabbitMQ**: AMQP message broker
- **Kafka**: Distributed streaming platform

### Full Stacks
- **WordPress**: With Nginx and Redis cache
- **Django**: With PostgreSQL and Redis
- **Nextcloud**: Self-hosted cloud storage

## Environment Variables

Each service includes a `.env.example` file with all configurable options. Key patterns:

```bash
# Service ports
SERVICE_PORT=8080

# Credentials (always change these!)
DB_PASSWORD=changeme
ADMIN_PASSWORD=changeme

# Feature flags
ENABLE_FEATURE=true

# Resource limits
MAX_MEMORY=256m
```

## Security Best Practices

1. **Change all default passwords** in `.env` files
2. **Use Docker secrets** for sensitive data in production
3. **Run containers as non-root** users
4. **Enable firewalls** to restrict access
5. **Use SSL/TLS** for external connections
6. **Regular updates** of images and host system
7. **Monitor logs** for suspicious activity

## Networking

Services use isolated Docker networks:
- Internal services communicate via service names
- Only required ports are exposed to host
- Use Traefik for SSL termination and routing

## Backup Strategies

### Database Backups
```bash
# PostgreSQL
docker exec postgres pg_dump -U postgres dbname > backup.sql

# MySQL
docker exec mysql mysqldump -u root -p dbname > backup.sql

# MongoDB
docker exec mongodb mongodump --out /backup
```

### Volume Backups
```bash
# Backup volume
docker run --rm -v volume_name:/data -v $(pwd):/backup \
  alpine tar czf /backup/volume_backup.tar.gz -C /data .

# Restore volume
docker run --rm -v volume_name:/data -v $(pwd):/backup \
  alpine tar xzf /backup/volume_backup.tar.gz -C /data
```

## Troubleshooting

### Check Service Status
```bash
docker compose ps
docker compose logs service_name
```

### Validate Docker Installation
```bash
./scripts/validate-environment.sh
```

### Common Issues

1. **Permission denied**: Run `newgrp docker` or logout/login
2. **Port already in use**: Change port in `.env` file
3. **Cannot connect**: Check firewall and network settings
4. **Out of space**: Clean up with `docker system prune -a`

## Contributing

1. Follow existing directory structure
2. Include comprehensive README for each service
3. Provide `.env.example` with all options
4. Implement health checks
5. Use official images when possible
6. Test on multiple distributions

## License

MIT License - See LICENSE file for details

## Support

- Create an issue for bugs or feature requests
- Check service-specific README files
- Review Docker logs for troubleshooting