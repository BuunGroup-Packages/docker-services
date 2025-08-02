#!/bin/bash

# Generate Vault configuration from template based on TLS settings

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/../config"

# Check if TLS is enabled
if [ "${VAULT_TLS_ENABLED:-false}" = "true" ]; then
    echo "Generating TLS-enabled Vault configuration..."
    
    # TLS listener config
    export VAULT_LISTENER_TLS_CONFIG='tls_cert_file      = "/vault/tls/vault.crt"
  tls_key_file       = "/vault/tls/vault.key"
  tls_client_ca_file = "/vault/tls/ca.crt"'
    
    # TLS retry join config
    export VAULT_TLS_CONFIG='leader_ca_cert_file = "/vault/tls/ca.crt"
    leader_client_cert_file = "/vault/tls/vault.crt"
    leader_client_key_file = "/vault/tls/vault.key"'
    
    # API addresses with HTTPS
    export VAULT_API_ADDR="https://vault:8200"
    export VAULT_CLUSTER_ADDR="https://vault:8201"
    export VAULT_LEADER_API_ADDR="https://vault:8200"
else
    echo "Generating non-TLS Vault configuration..."
    
    # Non-TLS config (empty)
    export VAULT_LISTENER_TLS_CONFIG='tls_disable = 1'
    export VAULT_TLS_CONFIG=""
    
    # API addresses with HTTP
    export VAULT_API_ADDR="http://vault:8200"
    export VAULT_CLUSTER_ADDR="http://vault:8201"
    export VAULT_LEADER_API_ADDR="http://vault:8200"
fi

# Generate configuration from template
envsubst < "$CONFIG_DIR/vault.hcl.template" > "$CONFIG_DIR/vault.hcl"

echo "Vault configuration generated successfully!"