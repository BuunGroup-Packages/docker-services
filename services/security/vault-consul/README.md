# HashiCorp Vault with Consul Storage Backend

Enterprise-grade Vault setup using Consul for distributed storage and service discovery.

## Features

- **Distributed Storage**: Consul provides consistent, distributed storage
- **Service Discovery**: Automatic Vault service registration
- **High Availability**: Active/Standby with automatic failover
- **Health Checking**: Built-in health checks for all services
- **Scalability**: Easy to scale Consul cluster
- **Load Balancing**: HAProxy for distributing traffic

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Consul 1   │────│  Consul 2   │────│  Consul 3   │
│   (Leader)  │    │  (Follower) │    │  (Follower) │
└─────────────┘    └─────────────┘    └─────────────┘
       │                  │                  │
       └──────────────────┴──────────────────┘
                          │
       ┌──────────────────┴──────────────────┐
       │                  │                  │
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Vault 1   │    │   Vault 2   │    │   Vault 3   │
│   (Active)  │    │  (Standby)  │    │  (Standby)  │
└─────────────┘    └─────────────┘    └─────────────┘
       │                  │                  │
       └──────────────────┴──────────────────┘
                          │
                    ┌─────────────┐
                    │   HAProxy   │
                    └─────────────┘
```

## Quick Start

### 1. Generate Consul Encryption Key

```bash
docker run --rm hashicorp/consul:latest consul keygen
# Add the output to CONSUL_ENCRYPT_KEY in .env
```

### 2. Start the Stack

```bash
# Copy environment file
cp .env.example .env

# Update CONSUL_ENCRYPT_KEY with generated key

# Start all services
docker compose up -d
```

### 3. Initialize Vault

```bash
docker compose --profile init up vault-init
```

This will:
- Initialize Vault with 5 keys (threshold 3)
- Save keys to `vault_keys` volume
- Automatically unseal the first Vault node
- Enable audit logging
- Create basic auth and secrets engines

### 4. Access Services

- Vault UI: `http://localhost:8200`
- Consul UI: `http://localhost:8500`
- HAProxy Stats: `http://localhost:8404/stats`

## High Availability Operations

### Check Cluster Status

```bash
# Consul cluster
docker exec consul-server-1 consul members

# Vault cluster
docker exec vault-1 vault operator members
```

### Unseal Additional Vault Nodes

```bash
# Get unseal keys
docker exec vault-init cat /vault/keys/unseal-keys.txt

# Unseal vault-2
docker exec vault-2 vault operator unseal <key1>
docker exec vault-2 vault operator unseal <key2>
docker exec vault-2 vault operator unseal <key3>

# Unseal vault-3
docker exec vault-3 vault operator unseal <key1>
docker exec vault-3 vault operator unseal <key2>
docker exec vault-3 vault operator unseal <key3>
```

### Force Failover

```bash
# Step down active node
docker exec vault-1 vault operator step-down
```

## Consul Operations

### View Consul Services

```bash
# List all services
docker exec consul-server-1 consul catalog services

# View Vault service details
docker exec consul-server-1 consul catalog nodes -service=vault
```

### Consul Key-Value Store

```bash
# Set a value
docker exec consul-server-1 consul kv put myapp/config/db_host "localhost"

# Get a value
docker exec consul-server-1 consul kv get myapp/config/db_host

# List keys
docker exec consul-server-1 consul kv get -recurse myapp/
```

### Consul ACLs (Production)

Enable ACLs for production:

1. Update `config/consul/consul.json`:
   ```json
   "acl": {
     "enabled": true,
     "default_policy": "deny"
   }
   ```

2. Bootstrap ACLs:
   ```bash
   docker exec consul-server-1 consul acl bootstrap
   ```

3. Create Vault policy:
   ```bash
   docker exec consul-server-1 consul acl policy create \
     -name vault-service \
     -rules @vault-consul-policy.hcl
   ```

## Vault-Consul Integration

### Dynamic Consul Credentials

```bash
# Configure Consul secrets engine
vault write consul/config/access \
  address="consul-server-1:8500" \
  token="<consul-management-token>"

# Create a role
vault write consul/roles/webapp \
  policies="webapp"

# Generate credentials
vault read consul/creds/webapp
```

### Service Registration

Vault automatically registers with Consul. View in Consul UI or:

```bash
docker exec consul-server-1 consul catalog services
```

## Backup and Restore

### Consul Backup

```bash
# Take snapshot
docker exec consul-server-1 consul snapshot save /consul/data/backup.snap

# Copy locally
docker cp consul-server-1:/consul/data/backup.snap ./backups/

# Restore
docker cp ./backups/backup.snap consul-server-1:/tmp/
docker exec consul-server-1 consul snapshot restore /tmp/backup.snap
```

### Vault Backup

Since data is in Consul, backup Consul. Additionally:

```bash
# Export policies
for policy in $(docker exec vault-1 vault policy list); do
  docker exec vault-1 vault policy read $policy > policies/$policy.hcl
done

# Export auth methods
docker exec vault-1 vault auth list -format=json > auth-methods.json
```

## Monitoring

### Health Endpoints

- Vault: `http://localhost:8200/v1/sys/health`
- Consul: `http://localhost:8500/v1/status/leader`
- HAProxy: `http://localhost:8404/stats`

### Prometheus Metrics

Both Vault and Consul expose Prometheus metrics:

- Vault: `http://localhost:8200/v1/sys/metrics`
- Consul: `http://localhost:8500/v1/agent/metrics`

### Logs

```bash
# Vault logs
docker compose logs vault-1

# Consul logs
docker compose logs consul-server-1

# Audit logs
docker exec vault-1 tail -f /vault/logs/audit.log | jq
```

## Performance Tuning

### Consul Performance

```json
{
  "performance": {
    "raft_multiplier": 1,
    "leave_drain_time": "5s",
    "rpc_hold_timeout": "7s"
  }
}
```

### Vault Performance

```hcl
# In vault.hcl
cache_size = 131072
disable_cache = false
```

### Network Optimization

- Keep Vault and Consul nodes in same network/datacenter
- Use dedicated network for cluster communication
- Monitor network latency between nodes

## Security Hardening

### Enable TLS

1. Generate certificates (see `scripts/generate-tls.sh`)
2. Update configurations to enable TLS
3. Set `VAULT_TLS_DISABLE=0` in `.env`

### Consul Encryption

- Gossip encryption: Already configured via `CONSUL_ENCRYPT_KEY`
- RPC encryption: Enable TLS
- ACLs: Enable and configure policies

### Vault Hardening

- Enable audit logging (done in init)
- Use auto-unseal
- Implement strict policies
- Rotate root token
- Enable MFA for sensitive operations

## Troubleshooting

### Consul Issues

```bash
# Check raft peers
docker exec consul-server-1 consul operator raft list-peers

# Check autopilot status
docker exec consul-server-1 consul operator autopilot get-config

# Force remove failed server
docker exec consul-server-1 consul operator raft remove-peer -id=<node-id>
```

### Vault Issues

```bash
# Check storage
docker exec vault-1 vault operator diagnose -storage

# Check replication status
docker exec vault-1 vault read sys/replication/status

# Force step-down
docker exec vault-1 vault operator step-down
```

### Common Problems

1. **Split Brain**: Check Consul leader election
2. **Vault Sealed**: Unseal with 3 keys
3. **High CPU**: Check Consul raft multiplier
4. **Storage Errors**: Verify Consul health

## Migration Guide

### From File/Raft to Consul

```bash
# 1. Take backup from existing Vault
vault operator migrate -config=migrate.hcl

# 2. Initialize new Consul-backed Vault
# 3. Restore data
vault operator migrate -config=restore.hcl
```

## Best Practices

1. **Consul Cluster**: Always run odd number (3, 5, 7)
2. **Backup Regularly**: Automate Consul snapshots
3. **Monitor Everything**: Use Prometheus + Grafana
4. **Secure Communications**: Enable TLS everywhere
5. **Access Control**: Implement Consul ACLs
6. **Separate Concerns**: Dedicated Consul cluster for Vault
7. **Resource Allocation**: Consul needs more resources than Vault