#!/bin/sh
set -e

# If VAULT_RAFT_NODE_ID is set, update the config
if [ -n "$VAULT_RAFT_NODE_ID" ]; then
    echo "Setting node_id to: $VAULT_RAFT_NODE_ID"
    
    # Determine which certificate to use based on node ID
    case "$VAULT_RAFT_NODE_ID" in
        vault_1)
            CERT_NAME="vault"
            ;;
        vault_2)
            CERT_NAME="vault-2"
            ;;
        vault_3)
            CERT_NAME="vault-3"
            ;;
        *)
            CERT_NAME="vault"
            ;;
    esac
    
    # Check if certificates exist
    if [ ! -f "/vault/tls/${CERT_NAME}.pem" ]; then
        echo "ERROR: Certificate /vault/tls/${CERT_NAME}.pem not found!"
        ls -la /vault/tls/
        exit 1
    fi
    
    # Create a writable directory for certificates
    mkdir -p /tmp/vault-certs
    
    # Copy certificates to temp directory
    cp /vault/tls/${CERT_NAME}.pem /tmp/vault-certs/
    cp /vault/tls/${CERT_NAME}-key.pem /tmp/vault-certs/
    cp /vault/tls/vault-ca.pem /tmp/vault-certs/
    
    # Set proper permissions
    chmod 600 /tmp/vault-certs/*-key.pem
    chmod 644 /tmp/vault-certs/*.pem
    
    # Determine the correct API and cluster addresses based on node ID
    case "$VAULT_RAFT_NODE_ID" in
        vault_1)
            API_ADDR="https://vault:8200"
            CLUSTER_ADDR="https://vault:8201"
            ;;
        vault_2)
            API_ADDR="https://vault-2:8200"
            CLUSTER_ADDR="https://vault-2:8201"
            ;;
        vault_3)
            API_ADDR="https://vault-3:8200"
            CLUSTER_ADDR="https://vault-3:8201"
            ;;
        *)
            API_ADDR="https://vault:8200"
            CLUSTER_ADDR="https://vault:8201"
            ;;
    esac
    
    # Create a copy of the config with the correct node_id, cert paths, and addresses
    sed -e "s/VAULT_RAFT_NODE_ID_PLACEHOLDER/$VAULT_RAFT_NODE_ID/g" \
        -e "s|/vault/config/vault.pem|/tmp/vault-certs/${CERT_NAME}.pem|g" \
        -e "s|/vault/config/vault-key.pem|/tmp/vault-certs/${CERT_NAME}-key.pem|g" \
        -e "s|/vault/config/vault-ca.pem|/tmp/vault-certs/vault-ca.pem|g" \
        -e "s|api_addr = \"https://0.0.0.0:8200\"|api_addr = \"$API_ADDR\"|g" \
        -e "s|cluster_addr = \"https://0.0.0.0:8201\"|cluster_addr = \"$CLUSTER_ADDR\"|g" \
        /vault/config/vault.hcl > /tmp/vault.hcl
    
    # Use the modified config
    exec vault server -config=/tmp/vault.hcl
else
    # Use default config
    exec vault server -config=/vault/config
fi