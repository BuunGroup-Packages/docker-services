# n8n - Workflow Automation Platform

Free and open fair-code licensed workflow automation tool.

## Features

- Visual workflow editor
- 350+ integrations (nodes)
- Webhook triggers
- Scheduled workflows
- Code execution (JavaScript/Python)
- API endpoints
- Error handling and retry logic
- Version control for workflows
- Team collaboration
- Self-hosted with full data control

## Quick Start

1. Copy environment file:
   ```bash
   cp .env.example .env
   ```

2. Generate encryption key:
   ```bash
   openssl rand -hex 32
   ```
   Add to `N8N_ENCRYPTION_KEY` in .env

3. Update passwords in `.env`

4. Start n8n:
   ```bash
   docker compose up -d
   ```

5. Access n8n at `http://localhost:5678`
   - Username: admin (from .env)
   - Password: your-password (from .env)

## Configuration

### Basic Setup

Essential environment variables:
- `N8N_ENCRYPTION_KEY`: Encrypts credentials (required)
- `N8N_BASIC_AUTH_USER/PASSWORD`: Web UI authentication
- `WEBHOOK_URL`: Public URL for webhooks

### Database

n8n uses PostgreSQL for:
- Workflow definitions
- Execution history
- Credentials storage
- User management

### Scaling with Workers

For high-volume processing:

```bash
# Enable queue mode in .env
EXECUTIONS_MODE=queue

# Start with workers
docker compose --profile worker up -d --scale n8n-worker=3
```

This runs:
- 1 main n8n instance (web UI + webhook receiver)
- 3 worker instances (execute workflows)
- Redis for job queue

## Workflows

### Backup Workflows

```bash
# Export all workflows
docker exec n8n n8n export:workflow --all --output=/backup/workflows.json

# Export specific workflow
docker exec n8n n8n export:workflow --id=1 --output=/backup/workflow-1.json

# Export credentials
docker exec n8n n8n export:credentials --all --output=/backup/credentials.json
```

### Import Workflows

```bash
# Import workflows
docker exec n8n n8n import:workflow --input=/backup/workflows.json

# Import credentials
docker exec n8n n8n import:credentials --input=/backup/credentials.json
```

### Version Control

Store workflows in `./workflows/` directory:

```bash
# Export for git
docker exec n8n n8n export:workflow --all --pretty --separate --output=/home/node/workflows/

# Commit to git
cd workflows && git add . && git commit -m "Update workflows"
```

## Common Integrations

### Webhooks

Create webhook URLs:
- Production: `https://n8n.yourdomain.com/webhook/xxx`
- Development: `http://localhost:5678/webhook/xxx`

### API Endpoints

Create custom API endpoints:
- Method: Webhook node with "Webhook" trigger
- Response: Respond to Webhook node

### Scheduled Tasks

Use Cron node:
- Every hour: `0 * * * *`
- Daily at 2 AM: `0 2 * * *`
- Every Monday: `0 0 * * 1`

## Security

### Credentials

- Stored encrypted in database
- Encryption key required for decryption
- Never expose `N8N_ENCRYPTION_KEY`

### Network Security

```yaml
# Restrict to internal network only
ports:
  - "127.0.0.1:5678:5678"
```

### Environment Variables in Workflows

Access environment variables:
```javascript
// In Function node
const apiKey = $env.MY_API_KEY;
```

Add to docker-compose.yml:
```yaml
environment:
  - MY_API_KEY=${MY_API_KEY}
```

## Performance Optimization

### Execution Pruning

Configure in UI or environment:
```bash
# Delete executions older than 14 days
EXECUTIONS_DATA_MAX_AGE=336

# Keep max 10000 executions
EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
EXECUTIONS_DATA_SAVE_ON_ERROR=all
EXECUTIONS_DATA_SAVE_ON_PROGRESS=false
EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true
```

### Binary Data

Configure storage:
```bash
# Store binary data for 24 hours
N8N_PERSISTED_BINARY_DATA_TTL=1440

# Use S3 for binary data (optional)
N8N_BINARY_DATA_MODE=s3
N8N_BINARY_DATA_S3_BUCKET=n8n-binary
```

### Memory Limits

Add to docker-compose.yml:
```yaml
deploy:
  resources:
    limits:
      memory: 2G
```

## Monitoring

### Health Check

- Endpoint: `http://localhost:5678/healthz`
- Returns 200 when healthy

### Prometheus Metrics

Enable metrics:
```bash
N8N_METRICS=true
```

Access at: `http://localhost:5678/metrics`

### Logs

View logs:
```bash
# All logs
docker compose logs n8n

# Follow logs
docker compose logs -f n8n

# Worker logs
docker compose logs n8n-worker
```

## Backup and Restore

### Full Backup

```bash
# Stop n8n
docker compose stop n8n

# Backup database
docker exec n8n-postgres pg_dump -U n8n n8n > backup.sql

# Backup data volume
docker run --rm -v n8n_data:/data -v $(pwd):/backup \
  alpine tar czf /backup/n8n-data-backup.tar.gz -C /data .

# Start n8n
docker compose start n8n
```

### Restore

```bash
# Stop n8n
docker compose stop n8n

# Restore database
docker exec -i n8n-postgres psql -U n8n n8n < backup.sql

# Restore data volume
docker run --rm -v n8n_data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/n8n-data-backup.tar.gz -C /data

# Start n8n
docker compose start n8n
```

## Troubleshooting

### Common Issues

1. **"Invalid encryption key"**
   - Ensure `N8N_ENCRYPTION_KEY` is set
   - Use the same key across restarts

2. **Workflows not executing**
   - Check execution mode settings
   - Verify webhook URL is accessible
   - Check worker logs if using queue mode

3. **High memory usage**
   - Enable execution pruning
   - Reduce binary data TTL
   - Scale with workers

4. **Webhook timeout**
   - Increase timeout in webhook node
   - Use queue mode for long-running workflows

### Debug Mode

Enable debug logging:
```bash
N8N_LOG_LEVEL=debug
docker compose up
```

## Integration Examples

### Slack Notification

```javascript
// Error notification workflow
1. Error Trigger node
2. Slack node: Send message to #alerts
```

### Database Sync

```javascript
// Sync data between databases
1. Cron node: Every hour
2. Postgres node: Read source data
3. Transform data (Function node)
4. MySQL node: Insert/update destination
```

### API Gateway

```javascript
// Create REST API
1. Webhook node: POST /api/process
2. Validate input (IF node)
3. Process data (HTTP Request node)
4. Respond to Webhook
```