# HashiCorp Vault with Raft Storage Backend

Production-ready Vault setup using integrated Raft storage for high availability.

## Features

- **Integrated Storage**: Raft consensus protocol built into Vault
- **High Availability**: 3-node cluster with automatic leader election
- **No External Dependencies**: No need for Consul or external databases
- **Automatic Backups**: Built-in snapshot capabilities
- **Simple Operations**: Easier to manage than external storage backends
- **Load Balancing**: HAProxy for distributing client requests

## Architecture

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Vault 1   │────│   Vault 2   │────│   Vault 3   │
│   (Raft)    │    │   (Raft)    │    │   (Raft)    │
└─────────────┘    └─────────────┘    └─────────────┘
       │                  │                  │
       └──────────────────┴──────────────────┘
                          │
                    ┌─────────────┐
                    │   HAProxy   │
                    │  (LB:8200)  │
                    └─────────────┘
```

## Quick Start (Single Node)

1. Copy environment file:
   ```bash
   cp .env.example .env
   ```

2. Start single Vault node:
   ```bash
   docker compose up -d
   ```

3. Initialize Vault:
   ```bash
   docker compose --profile init up vault-init
   ```

4. Access Vault UI at `http://localhost:8200`

## High Availability Setup (3 Nodes)

**Important**: This setup follows production Vault best practices where only the active node is unsealed. Secondary nodes remain sealed but are part of the cluster and can be manually promoted if the active node fails.

### 1. Start HA Cluster

```bash
# Start all nodes with HAProxy
docker compose --profile ha up -d
```

This starts:
- 3 Vault nodes (ports 8200, 8210, 8220)
- HAProxy load balancer (port 8300)
- HAProxy stats (port 8404)

### 2. Initialize and Setup Cluster

```bash
# Run the automated initialization script
docker compose --profile init run --rm vault-init
```

This script will:
1. Initialize the Vault cluster
2. Unseal the primary node (vault)
3. Join secondary nodes (vault-2, vault-3) to the cluster
4. Configure audit logging, auth methods, and KV engine
5. Apply production-ready security policies
6. Create default users with appropriate policies
7. Save unseal keys to `vault_keys` volume

**Note**: Secondary nodes will remain sealed. This is normal and follows Vault production patterns.

#### Default Users Created

| Username | Default Password | Policy | Access Level |
|----------|-----------------|--------|--------------|
| admin | admin-changeme | admin | Full administrative access |
| developer | dev-changeme | developer | Developer resources & personal namespace |
| cicd | cicd-changeme | cicd | CI/CD deployment access |
| auditor | auditor-changeme | auditor | Read-only audit access |

**Important**: Change these passwords immediately in production by setting environment variables in `.env`

### 3. Access Vault

- **Recommended**: Access through HAProxy at `http://localhost:8300`
- HAProxy automatically routes to the active (unsealed) node
- Direct node access: `http://localhost:8200`, `http://localhost:8210`, `http://localhost:8220`
- HAProxy stats: `http://localhost:8404/stats`

### 4. Verify Cluster Status

```bash
# Export credentials for easier management
export VAULT_ADDR='http://localhost:8200'  # Or http://localhost:8300 for HAProxy
export VAULT_TOKEN=$(docker run --rm -v vault-raft_vault_keys:/vault/keys busybox cat /vault/keys/root-token.txt)

# Check cluster members
docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault operator raft list-peers

# Expected output:
# Node       Address         State       Voter
# ----       -------         -----       -----
# vault_1    vault:8201      leader      true
# vault_2    vault-2:8201    follower    false
# vault_3    vault-3:8201    follower    false

# Check node health status
docker exec vault vault status
docker exec vault-2 vault status  # Will show sealed=true
docker exec vault-3 vault status  # Will show sealed=true

# Verify replication status
docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault read sys/replication/status

# Check HAProxy is routing correctly
curl -s http://localhost:8300/v1/sys/health | jq

# View audit logs
docker exec vault tail -f /vault/logs/audit.log | jq
```

### 5. Manual Failover (If Needed)

If the active node fails, manually unseal a secondary:

```bash
# Get unseal keys
docker run --rm -v vault-raft_vault_keys:/vault/keys busybox cat /vault/keys/unseal-keys.txt

# Unseal vault-2 (provide 3 keys when prompted)
docker exec -it vault-2 vault operator unseal
docker exec -it vault-2 vault operator unseal
docker exec -it vault-2 vault operator unseal
```

## Raft Operations

### List Peers

```bash
docker exec vault vault operator raft list-peers
```

### Take Snapshot

```bash
# Manual snapshot
docker exec vault vault operator raft snapshot save /vault/data/snapshot.snap

# Download snapshot
docker cp vault:/vault/data/snapshot.snap ./backups/
```

### Restore Snapshot

```bash
# Copy snapshot to container
docker cp ./backups/snapshot.snap vault:/tmp/

# Restore (requires unsealed Vault)
docker exec vault vault operator raft snapshot restore /tmp/snapshot.snap
```

### Remove Peer

```bash
# Remove a node from cluster
docker exec vault vault operator raft remove-peer vault_3
```

### Join Existing Cluster

```bash
# On new node
docker exec new-vault vault operator raft join http://vault:8200
```

## Auto-Unseal Configuration

### AWS KMS

1. Update `.env`:
   ```bash
   VAULT_SEAL_TYPE=awskms
   VAULT_AWSKMS_SEAL_KEY_ID=your-kms-key-id
   VAULT_AWSKMS_SEAL_REGION=us-east-1
   AWS_ACCESS_KEY_ID=your-access-key
   AWS_SECRET_ACCESS_KEY=your-secret-key
   ```

2. Uncomment seal configuration in `config/vault.hcl`

### Azure Key Vault

1. Update `.env` with Azure credentials
2. Uncomment Azure seal configuration in `config/vault.hcl`

### Benefits of Auto-Unseal

- Vault automatically unseals on restart
- No need to provide unseal keys manually
- More secure - unseal keys never touch disk
- Supports key rotation

## Backup Strategies

### Automated Snapshots

Create a cron job for regular snapshots:

```bash
# backup-vault.sh
#!/bin/bash
DATE=$(date +%Y%m%d-%H%M%S)
docker exec vault vault operator raft snapshot save /vault/data/snapshot-$DATE.snap
docker cp vault:/vault/data/snapshot-$DATE.snap ./backups/
find ./backups -name "snapshot-*.snap" -mtime +7 -delete
```

### Backup Retention

```bash
# Add to crontab
0 2 * * * /path/to/backup-vault.sh
```

## Monitoring

### Health Checks

- Single node: `http://localhost:8200/v1/sys/health`
- Cluster via HAProxy: `http://localhost:8300/v1/sys/health?standbyok=true`

### HAProxy Stats

Access statistics at `http://localhost:8404/stats`

### Metrics

```bash
# Enable Prometheus metrics
curl -X POST http://localhost:8200/v1/sys/metrics/config \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -d '{"prometheus_retention_time": "30s"}'
```

## Performance Tuning

### Raft Performance

```hcl
storage "raft" {
  path = "/vault/data"
  node_id = "vault_1"
  
  # Performance parameters
  performance_multiplier = 1
  max_entry_size = "1MB"
  
  # Snapshot settings
  snapshot_threshold = "8192"
  snapshot_interval = "120s"
  trailing_logs = "10000"
}
```

### System Resources

For production:
- CPU: 2-4 cores per node
- RAM: 4-8GB per node
- Disk: Fast SSD with sufficient IOPS
- Network: Low latency between nodes (<10ms)

## Security Hardening

### Enable TLS

#### 1. Generate Certificates

```bash
# Generate CA and certificates for all nodes
./scripts/generate-tls.sh
```

This creates:
- CA certificate and key
- Individual certificates for each Vault node
- Client certificate for CLI access
- HAProxy bundle

#### 2. Deploy with TLS

```bash
# For single node with TLS
docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d

# For HA mode with TLS
docker compose -f docker-compose.yml -f docker-compose.tls.yml --profile ha up -d

# Initialize with TLS
docker compose -f docker-compose.yml -f docker-compose.tls.yml --profile init run --rm vault-init
```

#### 3. Configure Client Access

```bash
# Set environment variables for TLS
export VAULT_ADDR='https://localhost:8200'  # or https://localhost:8300 for HAProxy
export VAULT_CACERT=$PWD/certs/vault-ca.pem
export VAULT_CLIENT_CERT=$PWD/certs/vault-client.pem
export VAULT_CLIENT_KEY=$PWD/certs/vault-client-key.pem

# Test connection
vault status
```

#### 4. Certificate Details

The generated certificates include:
- **Subject Alternative Names**: Each node's hostname, Docker network name, localhost, and IP addresses
- **Key Usage**: Server and client authentication
- **Validity**: 10 years (configurable in script)
- **Key Size**: 4096-bit RSA

#### 5. Production Considerations

For production environments:
- Use certificates from a trusted CA
- Implement certificate rotation
- Enable `tls_require_and_verify_client_cert` for mutual TLS
- Use stronger cipher suites if needed
- Store private keys securely (consider HSM)

### Audit Logging

Automatically enabled during initialization. View logs:

```bash
docker exec vault tail -f /vault/logs/audit.log | jq
```

### Production-Ready Policies

#### 1. Admin Policy (for DevOps teams)
Create `policies/admin.hcl`:
```hcl
# Manage auth methods broadly across Vault
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# Create, update, and delete auth methods
path "sys/auth/*" {
  capabilities = ["create", "update", "delete", "sudo"]
}

# List auth methods
path "sys/auth" {
  capabilities = ["read"]
}

# Manage secrets engines
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}

# List secrets engines
path "sys/mounts" {
  capabilities = ["read", "list"]
}

# Create and manage policies
path "sys/policies/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Capabilities on all secrets
path "*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

#### 2. Developer Policy
Create `policies/developer.hcl`:
```hcl
# Developers can read their app secrets
path "secret/data/{{identity.entity.aliases.auth_userpass_*.name}}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Read-only access to shared configs
path "secret/data/shared/*" {
  capabilities = ["read", "list"]
}

# Create and manage their own KV secrets
path "secret/data/dev/{{identity.entity.aliases.auth_userpass_*.name}}/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# List all paths in dev
path "secret/metadata/dev/*" {
  capabilities = ["list"]
}

# Generate database credentials
path "database/creds/dev-*" {
  capabilities = ["read"]
}

# Encrypt/decrypt with transit
path "transit/encrypt/app-*" {
  capabilities = ["update"]
}

path "transit/decrypt/app-*" {
  capabilities = ["update"]
}
```

#### 3. Application Policy (for services)
Create `policies/application.hcl`:
```hcl
# Read app-specific secrets
path "secret/data/apps/{{identity.entity.name}}/*" {
  capabilities = ["read"]
}

# Renew its own token
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Lookup its own token info
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Generate database credentials for the app
path "database/creds/{{identity.entity.name}}-db" {
  capabilities = ["read"]
}

# Use transit encryption for the app
path "transit/encrypt/{{identity.entity.name}}" {
  capabilities = ["update"]
}

path "transit/decrypt/{{identity.entity.name}}" {
  capabilities = ["update"]
}
```

#### 4. CI/CD Pipeline Policy
Create `policies/cicd.hcl`:
```hcl
# Read deployment secrets
path "secret/data/ci/*" {
  capabilities = ["read", "list"]
}

# Manage app secrets during deployment
path "secret/data/apps/*/config" {
  capabilities = ["create", "read", "update"]
}

# Generate temporary credentials
path "aws/creds/deploy" {
  capabilities = ["read"]
}

path "database/creds/app-*" {
  capabilities = ["read"]
}

# Sign SSH certificates for deployment
path "ssh-client-signer/sign/deploy" {
  capabilities = ["update"]
}
```

#### 5. Auditor Policy (read-only access)
Create `policies/auditor.hcl`:
```hcl
# Read access to all secrets metadata
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}

# View audit logs configuration
path "sys/audit" {
  capabilities = ["read", "list"]
}

# View all policies
path "sys/policies/*" {
  capabilities = ["read", "list"]
}

# View all auth methods
path "sys/auth" {
  capabilities = ["read", "list"]
}

# View all mounts
path "sys/mounts" {
  capabilities = ["read", "list"]
}

# Cannot read actual secret values
path "secret/data/*" {
  capabilities = ["deny"]
}
```

#### Apply Policies

```bash
# Export token if not already done
export VAULT_TOKEN=$(docker run --rm -v vault-raft_vault_keys:/vault/keys busybox cat /vault/keys/root-token.txt)

# Apply all policies
docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault policy write admin /vault/policies/admin.hcl
docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault policy write developer /vault/policies/developer.hcl
docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault policy write application /vault/policies/application.hcl
docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault policy write cicd /vault/policies/cicd.hcl
docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault policy write auditor /vault/policies/auditor.hcl

# List all policies
docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault policy list
```

#### Create Users with Policies

```bash
# Create admin user
docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault write auth/userpass/users/admin \
  password=changeme \
  policies=admin

# Create developer user
docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault write auth/userpass/users/developer \
  password=changeme \
  policies=developer

# Create CI/CD service account
docker exec -e VAULT_TOKEN=$VAULT_TOKEN vault vault write auth/userpass/users/cicd \
  password=changeme \
  policies=cicd
```

## Troubleshooting

### Node Won't Join Cluster

1. Check network connectivity
2. Verify node IDs are unique
3. Check cluster address configuration
4. Review logs: `docker compose logs vault-2`

### Split Brain

If cluster splits:
1. Stop all nodes
2. Choose one node as leader
3. On chosen node: `vault operator raft snapshot save backup.snap`
4. Wipe data on other nodes
5. Restart chosen node
6. Join other nodes to cluster

### Performance Issues

1. Check disk I/O: `docker exec vault iostat -x 1`
2. Monitor Raft metrics
3. Increase performance_multiplier
4. Consider adding more nodes

## Migration from Other Backends

### From Consul

```bash
# 1. Take backup from Consul-backed Vault
vault operator migrate -config migrate.hcl

# 2. Initialize new Raft cluster
# 3. Restore data
vault operator raft snapshot restore backup.snap
```

### From File Storage

1. Export all secrets and policies
2. Initialize new Raft cluster
3. Import secrets and policies

## Best Practices

1. **Always run odd number of nodes** (3, 5, 7)
2. **Regular snapshots** - Automate daily backups
3. **Monitor cluster health** - Set up alerts
4. **Test disaster recovery** - Practice restore procedures
5. **Use auto-unseal** - Eliminate manual unseal process
6. **Enable audit logs** - Track all operations
7. **Implement least privilege** - Use policies extensively