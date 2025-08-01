# Vault HA TLS Configuration Testing Guide

## Issues Fixed in Current Configuration

### 1. Path Consistency Issues
- **Problem**: Vault configuration referenced `/vault/config/` paths but entrypoint copied certs to `/tmp/vault-certs/`
- **Fix**: Updated `docker-entrypoint-tls.sh` to properly replace ALL certificate paths including Raft retry_join configurations

### 2. API/Cluster Address Configuration
- **Problem**: Used `0.0.0.0` addresses which don't work properly in HA clustering
- **Fix**: Dynamic address assignment based on node ID in entrypoint script

### 3. HAProxy Certificate Issues
- **Problem**: HAProxy used Vault node certificate without proper SANs
- **Fix**: Generated dedicated HAProxy certificate with appropriate Subject Alternative Names

### 4. Network Configuration
- **Problem**: Missing network configuration in TLS override
- **Fix**: Added proper network configuration with subnet definition

## Step-by-Step Testing Procedure

### Prerequisites
1. Ensure Docker and Docker Compose are installed
2. Navigate to the vault-raft directory: `cd services/security/vault-raft`
3. Ensure you have required tools: `openssl`, `curl`, `jq` (optional)

### Step 1: Clean Up Previous Deployments
```bash
# Stop and remove existing containers and volumes
docker compose -f docker-compose.yml -f docker-compose.tls.yml --profile ha down -v

# Remove any existing certificates
rm -rf certs tls
```

### Step 2: Generate TLS Certificates
```bash
# Generate certificates using the certificate generator
docker compose -f docker-compose.yml -f docker-compose.tls.yml --profile ha run --rm cert-generator

# Verify certificates were created
ls -la certs/
```

**Expected output should include:**
- `vault-ca.pem` - CA certificate
- `vault.pem`, `vault-2.pem`, `vault-3.pem` - Server certificates
- `haproxy.pem` - HAProxy certificate
- `haproxy-cert.pem` - HAProxy certificate bundle
- `vault-client.pem` - Client certificate
- All corresponding private keys (`*-key.pem`)

### Step 3: Start the TLS-Enabled Vault Cluster
```bash
# Start the complete HA cluster with TLS
docker compose -f docker-compose.yml -f docker-compose.tls.yml --profile ha up -d

# Check container status
docker compose -f docker-compose.yml -f docker-compose.tls.yml --profile ha ps
```

**All containers should show "healthy" or "running" status:**
- `cert-generator` - Should complete successfully
- `vault`, `vault-2`, `vault-3` - Should be running
- `vault-haproxy` - Should be running

### Step 4: Wait for Services to Initialize
```bash
# Wait for services to start (30-60 seconds)
sleep 30

# Check logs for any errors
docker compose -f docker-compose.yml -f docker-compose.tls.yml --profile ha logs vault
```

### Step 5: Run Comprehensive TLS Tests
```bash
# Run the automated TLS testing script
./scripts/test-tls.sh
```

**This script will test:**
1. Certificate file existence and validity
2. Network connectivity to all endpoints
3. TLS handshakes with all services
4. Vault API accessibility over TLS
5. HAProxy load balancing functionality
6. Certificate chain validation
7. Cipher suite and TLS version support

### Step 6: Manual Verification Steps

#### 6.1 Verify Certificate Details
```bash
# Check CA certificate
openssl x509 -in certs/vault-ca.pem -noout -text | grep -A 5 "Subject:"

# Check server certificate SANs
openssl x509 -in certs/vault.pem -noout -text | grep -A 10 "Subject Alternative Name"

# Check HAProxy certificate SANs
openssl x509 -in certs/haproxy.pem -noout -text | grep -A 10 "Subject Alternative Name"
```

#### 6.2 Test TLS Handshakes Manually
```bash
# Test HAProxy TLS handshake
echo | openssl s_client -connect localhost:8300 -CAfile certs/vault-ca.pem -verify_return_error

# Test direct Vault node handshake
echo | openssl s_client -connect localhost:8200 -CAfile certs/vault-ca.pem -verify_return_error
```

#### 6.3 Test Vault API with TLS
```bash
# Set environment variables
export VAULT_ADDR="https://localhost:8300"
export VAULT_CACERT="$(pwd)/certs/vault-ca.pem"

# Test API connectivity
curl --cacert certs/vault-ca.pem https://localhost:8300/v1/sys/health

# If vault CLI is installed
vault status
```

#### 6.4 Verify HAProxy Load Balancing
```bash
# Check HAProxy stats
curl -s http://localhost:8404/stats

# Check backend status in CSV format
curl -s http://localhost:8404/stats\;csv | grep vault
```

### Step 7: Initialize Vault (if needed)
```bash
# Initialize Vault through HAProxy
docker compose -f docker-compose.yml -f docker-compose.tls.yml --profile init run --rm vault-init

# Or manually initialize
vault operator init -key-shares=5 -key-threshold=3
```

### Step 8: Test End-to-End Functionality

#### 8.1 Unseal Vault Nodes
```bash
# Unseal each node (repeat for each unseal key)
vault operator unseal <unseal-key-1>
vault operator unseal <unseal-key-2>
vault operator unseal <unseal-key-3>
```

#### 8.2 Test HA Functionality
```bash
# Check cluster status
vault operator raft list-peers

# Test failover by stopping the active node
docker stop vault
sleep 5
vault status  # Should still work through HAProxy
```

## Common Issues and Solutions

### Issue 1: Certificate Verification Failed
**Symptoms**: TLS handshake errors, certificate verification failures
**Solutions**:
1. Check certificate SANs match the hostnames/IPs being used
2. Verify certificate hasn't expired: `openssl x509 -in cert.pem -noout -dates`
3. Ensure CA certificate is properly configured

### Issue 2: Connection Refused
**Symptoms**: Cannot connect to services on expected ports
**Solutions**:
1. Check if containers are running: `docker ps`
2. Verify port mappings in docker-compose files
3. Check firewall settings

### Issue 3: HAProxy Backend Down
**Symptoms**: HAProxy shows backends as down in stats
**Solutions**:
1. Check Vault node health: `vault status` on each node
2. Verify HAProxy can reach backend services
3. Check HAProxy configuration and certificate paths

### Issue 4: Vault Cluster Not Forming
**Symptoms**: Vault nodes don't join cluster, raft errors
**Solutions**:
1. Check node IDs are unique and properly set
2. Verify network connectivity between nodes
3. Check certificate paths in Vault configuration
4. Review Vault logs: `docker logs vault`

## Security Best Practices

### 1. Certificate Management
- Use strong key sizes (4096 bits minimum)
- Set appropriate certificate validity periods
- Implement certificate rotation procedures
- Store private keys securely with proper permissions (600)

### 2. TLS Configuration
- Use strong cipher suites (ECDHE+AESGCM)
- Disable weak TLS versions (< TLS 1.2)
- Enable certificate verification
- Use client certificates for enhanced security

### 3. Network Security
- Restrict network access to necessary ports only
- Use dedicated networks for inter-service communication
- Implement proper firewall rules
- Monitor network traffic

### 4. Monitoring and Logging
- Enable Vault audit logging
- Monitor certificate expiration dates
- Set up alerts for service health
- Regular security audits

## Verification Checklist

- [ ] All certificates generated successfully
- [ ] All containers start without errors
- [ ] TLS handshakes work for all endpoints
- [ ] Vault API accessible through HAProxy with TLS
- [ ] HAProxy load balancing working correctly
- [ ] Certificate chains validate properly
- [ ] Strong cipher suites supported
- [ ] Vault cluster formation successful
- [ ] Failover testing passed
- [ ] Client certificate authentication (if enabled)

## Troubleshooting Commands

```bash
# View container logs
docker compose -f docker-compose.yml -f docker-compose.tls.yml logs <service-name>

# Check certificate validity
openssl x509 -in <cert-file> -noout -dates -subject -issuer

# Test TLS connection
openssl s_client -connect <host>:<port> -CAfile <ca-cert> -verify_return_error

# Check HAProxy configuration
docker exec vault-haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

# Inspect Vault configuration
docker exec vault cat /tmp/vault.hcl

# Check network connectivity
docker exec vault ping vault-2
```

This guide provides comprehensive testing procedures to ensure your Vault HA TLS setup is working correctly. Follow each step carefully and address any issues before proceeding to production deployment.