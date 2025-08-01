#!/bin/sh
set -e

# If VAULT_RAFT_NODE_ID is set, update the config
if [ -n "$VAULT_RAFT_NODE_ID" ]; then
    echo "Setting node_id to: $VAULT_RAFT_NODE_ID"
    # Create a copy of the config with the correct node_id
    sed "s/VAULT_RAFT_NODE_ID_PLACEHOLDER/$VAULT_RAFT_NODE_ID/g" /vault/config/vault.hcl > /tmp/vault.hcl
    # Use the modified config
    exec vault server -config=/tmp/vault.hcl
else
    # Use default config
    exec vault server -config=/vault/config
fi