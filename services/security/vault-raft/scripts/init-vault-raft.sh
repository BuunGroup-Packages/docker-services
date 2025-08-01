#!/bin/sh

set -e

# Detect if we're running in HA mode by checking for other vault nodes
VAULT_NODES="vault"
if nc -z vault-2 8200 2>/dev/null; then
    VAULT_NODES="$VAULT_NODES vault-2 vault-3"
    echo "Detected HA mode with nodes: $VAULT_NODES"
else
    echo "Running in single-node mode"
fi

# Set primary Vault address based on environment
if [ -n "$VAULT_CACERT" ] && [ -f "$VAULT_CACERT" ]; then
    echo "TLS mode detected - using HTTPS"
    export VAULT_ADDR=${VAULT_ADDR:-https://vault:8200}
    # VAULT_CACERT should already be set by docker-compose.tls.yml
else
    echo "Non-TLS mode - using HTTP"
    export VAULT_ADDR=http://vault:8200
fi

echo "Waiting for Vault nodes to be ready..."
for node in $VAULT_NODES; do
    echo -n "Waiting for $node..."
    while ! nc -z $node 8200 2>/dev/null; do
        echo -n "."
        sleep 1
    done
    echo " ready!"
done

# Function to extract keys from JSON without jq
extract_unseal_keys() {
    # Extract the unseal_keys_b64 array and parse each key
    awk '
        /unseal_keys_b64/ {getline; collecting=1}
        collecting && /^\s*"/ {
            gsub(/[",]/, "", $0)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
            if ($0 != "") print $0
        }
        collecting && /\]/ {exit}
    ' /vault/keys/vault-init.json > /vault/keys/unseal-keys.txt
}

extract_root_token() {
    # Extract root token
    grep '"root_token"' /vault/keys/vault-init.json | sed 's/.*"root_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' > /vault/keys/root-token.txt
}

# Function to unseal a node
unseal_node() {
    local node=$1
    local protocol="http"
    if [ -n "$VAULT_CACERT" ] && [ -f "$VAULT_CACERT" ]; then
        protocol="https"
    fi
    local node_addr="$protocol://$node:8200"
    
    echo "Checking $node status..."
    
    # Set VAULT_SKIP_VERIFY for TLS connections
    if [ "$protocol" = "https" ]; then
        export VAULT_SKIP_VERIFY=true
    fi
    
    # Check if sealed
    if VAULT_ADDR=$node_addr vault status 2>&1 | grep -q "Sealed.*true"; then
        echo "Unsealing $node..."
        
        # Use first 3 keys to unseal
        for i in 1 2 3; do
            KEY=$(sed -n "${i}p" /vault/keys/unseal-keys.txt)
            if [ -n "$KEY" ]; then
                echo "  Applying unseal key $i..."
                if ! VAULT_ADDR=$node_addr vault operator unseal "$KEY" 2>&1 | grep -E "Unseal Progress|Error"; then
                    echo "    Key application completed"
                fi
            fi
        done
        
        # Give it a moment to process
        sleep 2
        
        # Verify unsealed
        if VAULT_ADDR=$node_addr vault status 2>&1 | grep -q "Sealed.*false"; then
            echo "✓ $node unsealed successfully"
        else
            echo "✗ Failed to unseal $node"
            return 1
        fi
    else
        echo "✓ $node is already unsealed"
    fi
}

# Check if any node is initialized
INITIALIZED=false
for node in $VAULT_NODES; do
    if VAULT_ADDR=http://$node:8200 vault status 2>&1 | grep -q "Initialized.*true"; then
        INITIALIZED=true
        echo "Vault cluster is already initialized"
        break
    fi
done

if [ "$INITIALIZED" = "false" ]; then
    echo ""
    echo "Initializing Vault cluster..."
    vault operator init \
        -key-shares=5 \
        -key-threshold=3 \
        -format=json > /vault/keys/vault-init.json
    
    echo "✓ Vault initialization complete!"
    echo "  Keys saved to /vault/keys/vault-init.json"
    
    # Extract keys and token
    extract_unseal_keys
    extract_root_token
    
    echo ""
    echo "IMPORTANT: Backup the initialization keys immediately!"
    echo "Location: /vault/keys/vault-init.json"
fi

# Ensure we have unseal keys
if [ ! -f /vault/keys/unseal-keys.txt ] || [ ! -s /vault/keys/unseal-keys.txt ]; then
    echo "Extracting unseal keys from existing initialization..."
    extract_unseal_keys
    extract_root_token
fi

# For HA mode, first unseal primary node, then join others
if [ "$VAULT_NODES" != "vault" ]; then
    echo ""
    echo "Unsealing primary node..."
    unseal_node vault
    
    echo ""
    echo "Joining secondary nodes to cluster..."
    protocol="http"
    if [ -n "$VAULT_CACERT" ] && [ -f "$VAULT_CACERT" ]; then
        protocol="https"
    fi
    
    # Get root token for authentication
    ROOT_TOKEN=$(cat /vault/keys/root-token.txt)
    export VAULT_TOKEN=$ROOT_TOKEN
    
    for node in vault-2 vault-3; do
        echo "Joining $node to cluster..."
        
        # Check if node is already initialized (has raft data)
        if [ "$protocol" = "https" ]; then
            export VAULT_SKIP_VERIFY=true
        fi
        
        # Try to check if already initialized
        if VAULT_ADDR=$protocol://$node:8200 vault status 2>&1 | grep -q "Initialized.*true"; then
            echo "  WARNING: $node appears to be already initialized"
            echo "  This can prevent it from joining the cluster"
            echo "  You may need to manually wipe its data volume and restart"
        fi
        
        # Try to join
        echo "  Attempting to join $node to leader at vault:8200..."
        if VAULT_ADDR=$protocol://$node:8200 vault operator raft join -leader-ca-cert="$(cat /vault/tls/vault-ca.pem)" $protocol://vault:8200 2>&1; then
            echo "  ✓ Successfully joined $node"
        else
            echo "  ✗ Failed to join $node - it may need its raft data cleared"
        fi
    done
    
    echo ""
    echo "Restarting secondary nodes to apply raft configuration..."
    # Use docker API from host to restart containers
    # This requires mounting docker socket in the init container
    if [ -S /var/run/docker.sock ]; then
        echo "  Restarting vault-2..."
        docker restart vault-2 >/dev/null 2>&1 || echo "    Failed to restart vault-2"
        echo "  Restarting vault-3..."
        docker restart vault-3 >/dev/null 2>&1 || echo "    Failed to restart vault-3"
        echo "  Waiting for nodes to come back online..."
        sleep 15
        
        # Wait for nodes to be ready again
        for node in vault-2 vault-3; do
            echo -n "  Waiting for $node..."
            attempts=0
            while ! nc -z $node 8200 2>/dev/null; do
                echo -n "."
                sleep 2
                attempts=$((attempts + 1))
                if [ $attempts -gt 30 ]; then
                    echo " timeout!"
                    break
                fi
            done
            echo " ready!"
        done
        
        # Give extra time for raft to stabilize
        echo "  Waiting for raft cluster to stabilize..."
        sleep 10
    else
        echo "  WARNING: Cannot restart containers automatically."
        echo "  Trying alternative approach without restart..."
        sleep 5
    fi
    
    echo ""
    echo "Checking cluster membership..."
    VAULT_ADDR=$protocol://vault:8200 vault operator raft list-peers || echo "  Unable to list peers"
    
    echo ""
    echo "Unsealing secondary nodes..."
    for node in vault-2 vault-3; do
        unseal_node $node || true
    done
else
    # Single node mode
    echo ""
    echo "Unsealing Vault..."
    unseal_node vault
fi

# Wait for cluster to stabilize
echo ""
echo "Waiting for cluster to elect a leader..."
sleep 5

# Find the active node
ACTIVE_NODE=""
for node in $VAULT_NODES; do
    if VAULT_ADDR=http://$node:8200 vault status 2>&1 | grep -q "HA Mode.*active"; then
        ACTIVE_NODE=$node
        break
    fi
done

if [ -z "$ACTIVE_NODE" ]; then
    echo "Warning: No active node found, using primary node"
    ACTIVE_NODE="vault"
fi

echo "Active node: $ACTIVE_NODE"
export VAULT_ADDR=http://$ACTIVE_NODE:8200

# Login with root token
if [ -f /vault/keys/root-token.txt ]; then
    ROOT_TOKEN=$(cat /vault/keys/root-token.txt)
    echo ""
    echo "Logging in to Vault..."
    vault login "$ROOT_TOKEN" >/dev/null 2>&1
    
    # Configure Vault (only on first init)
    if ! vault auth list 2>/dev/null | grep -q userpass; then
        echo ""
        echo "Performing initial Vault configuration..."
        
        echo "- Enabling audit logging..."
        vault audit enable file file_path=/vault/logs/audit.log 2>/dev/null || true
        
        echo "- Enabling userpass auth method..."
        vault auth enable userpass 2>/dev/null || true
        
        echo "- Creating KV v2 secrets engine..."
        vault secrets enable -version=2 -path=secret kv 2>/dev/null || true
        
        echo ""
        echo "Applying production policies..."
        
        # Apply all policies if they exist
        for policy in admin developer application cicd auditor; do
            if [ -f "/vault/policies/${policy}.hcl" ]; then
                echo "- Applying ${policy} policy..."
                vault policy write ${policy} /vault/policies/${policy}.hcl 2>/dev/null || echo "  Failed to apply ${policy} policy"
            fi
        done
        
        echo ""
        echo "Creating default users..."
        
        # Create admin user
        vault write auth/userpass/users/admin \
            password="${VAULT_ADMIN_PASSWORD:-admin-changeme}" \
            policies="admin" 2>/dev/null && echo "- Created admin user (password: ${VAULT_ADMIN_PASSWORD:-admin-changeme})"
        
        # Create developer user
        vault write auth/userpass/users/developer \
            password="${VAULT_DEV_PASSWORD:-dev-changeme}" \
            policies="developer" 2>/dev/null && echo "- Created developer user (password: ${VAULT_DEV_PASSWORD:-dev-changeme})"
        
        # Create CI/CD user
        vault write auth/userpass/users/cicd \
            password="${VAULT_CICD_PASSWORD:-cicd-changeme}" \
            policies="cicd" 2>/dev/null && echo "- Created cicd user (password: ${VAULT_CICD_PASSWORD:-cicd-changeme})"
        
        # Create auditor user
        vault write auth/userpass/users/auditor \
            password="${VAULT_AUDITOR_PASSWORD:-auditor-changeme}" \
            policies="auditor" 2>/dev/null && echo "- Created auditor user (password: ${VAULT_AUDITOR_PASSWORD:-auditor-changeme})"
        
        echo ""
        echo "✓ Initial configuration complete"
    fi
fi

# Display cluster status
echo ""
echo "=== Vault Cluster Status ==="
for node in $VAULT_NODES; do
    MODE=$(VAULT_ADDR=http://$node:8200 vault status 2>/dev/null | grep "HA Mode" | awk '{print $3}')
    SEALED=$(VAULT_ADDR=http://$node:8200 vault status 2>/dev/null | grep "Sealed" | awk '{print $2}')
    printf "%-10s: %-10s (sealed: %s)\n" "$node" "$MODE" "$SEALED"
done

echo ""
echo "=== Vault is ready! ==="
if [ -n "$ROOT_TOKEN" ]; then
    echo "Root token: $ROOT_TOKEN"
fi
echo ""
echo "Access Vault at:"
if [ -n "$VAULT_CACERT" ] && [ -f "$VAULT_CACERT" ]; then
    echo "- Single node: https://localhost:8200"
    if [ "$VAULT_NODES" != "vault" ]; then
        echo "- Load balanced: https://localhost:8300 (via HAProxy)"
        echo "- HAProxy stats: http://localhost:8404/stats"
    fi
    echo ""
    echo "TLS Configuration:"
    echo "  export VAULT_ADDR='https://localhost:8200'"
    echo "  export VAULT_CACERT=\$PWD/certs/vault-ca.pem"
else
    echo "- Single node: http://localhost:8200"
    if [ "$VAULT_NODES" != "vault" ]; then
        echo "- Load balanced: http://localhost:8300 (via HAProxy)"
        echo "- HAProxy stats: http://localhost:8404/stats"
    fi
fi