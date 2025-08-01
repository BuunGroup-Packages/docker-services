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
    if [ ! -f "/vault/config/certs/${CERT_NAME}.pem" ]; then
        echo "ERROR: Certificate /vault/config/certs/${CERT_NAME}.pem not found!"
        ls -la /vault/config/certs/
        exit 1
    fi
    
    # Copy certificates to config directory
    cp /vault/config/certs/${CERT_NAME}.pem /vault/config/
    cp /vault/config/certs/${CERT_NAME}-key.pem /vault/config/
    cp /vault/config/certs/vault-ca.pem /vault/config/
    
    # Create a copy of the config with the correct node_id and cert paths
    sed -e "s/VAULT_RAFT_NODE_ID_PLACEHOLDER/$VAULT_RAFT_NODE_ID/g" \
        -e "s|/vault/config/vault.pem|/vault/config/${CERT_NAME}.pem|g" \
        -e "s|/vault/config/vault-key.pem|/vault/config/${CERT_NAME}-key.pem|g" \
        /vault/config/vault.hcl > /tmp/vault.hcl
    
    # Use the modified config
    exec vault server -config=/tmp/vault.hcl
else
    # Use default config
    exec vault server -config=/vault/config
fi