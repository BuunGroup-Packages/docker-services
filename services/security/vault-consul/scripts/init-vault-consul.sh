#!/bin/sh

set -e

echo "Waiting for Vault to be ready..."
until vault status 2>/dev/null; do
    echo "Vault is not ready yet..."
    sleep 2
done

# Check if Vault is already initialized
if vault status 2>/dev/null | grep -q "Initialized.*true"; then
    echo "Vault is already initialized"
    
    # Check if we have unseal keys
    if [ -f /vault/keys/unseal-keys.txt ]; then
        echo "Attempting to unseal Vault..."
        SEALED=$(vault status -format=json | jq -r '.sealed')
        
        if [ "$SEALED" = "true" ]; then
            # Unseal with first 3 keys
            for i in 1 2 3; do
                KEY=$(sed -n "${i}p" /vault/keys/unseal-keys.txt)
                vault operator unseal "$KEY" || true
            done
            echo "Vault unsealed successfully!"
        else
            echo "Vault is already unsealed"
        fi
    fi
    exit 0
fi

echo "Checking Consul cluster health..."
until consul members 2>/dev/null | grep -q "alive"; do
    echo "Waiting for Consul cluster..."
    sleep 2
done

echo "Consul cluster is healthy"
consul members

echo ""
echo "Initializing Vault with Consul storage..."
vault operator init \
    -key-shares=5 \
    -key-threshold=3 \
    -format=json > /vault/keys/vault-init.json

echo "Vault initialization complete!"
echo "Keys saved to /vault/keys/vault-init.json"
echo ""
echo "IMPORTANT: Backup these keys immediately and store them securely!"
echo "You will need at least 3 keys to unseal Vault."

# Extract unseal keys and root token
cat /vault/keys/vault-init.json | jq -r '.unseal_keys_b64[]' > /vault/keys/unseal-keys.txt
cat /vault/keys/vault-init.json | jq -r '.root_token' > /vault/keys/root-token.txt

echo ""
echo "Unsealing Vault..."
for i in 1 2 3; do
    KEY=$(sed -n "${i}p" /vault/keys/unseal-keys.txt)
    vault operator unseal "$KEY"
done

echo "Vault unsealed successfully!"

# Wait for leader election
sleep 5

# Login with root token
ROOT_TOKEN=$(cat /vault/keys/root-token.txt)
vault login "$ROOT_TOKEN"

echo ""
echo "Enabling audit logging..."
vault audit enable file file_path=/vault/logs/audit.log || true

echo ""
echo "Creating basic auth method..."
vault auth enable userpass || true

echo ""
echo "Creating basic secrets engine..."
vault secrets enable -version=2 -path=secret kv || true

echo ""
echo "Creating Consul secrets engine..."
vault secrets enable consul || true

# Configure Consul access
echo ""
echo "Configuring Consul access..."
CONSUL_TOKEN=$(consul acl bootstrap -format=json 2>/dev/null | jq -r '.SecretID' || echo "")
if [ -n "$CONSUL_TOKEN" ]; then
    vault write consul/config/access \
        address="consul-server-1:8500" \
        token="$CONSUL_TOKEN"
    echo "Consul Token: $CONSUL_TOKEN" > /vault/keys/consul-token.txt
fi

echo ""
echo "Vault is ready for use!"
echo "Root token: $ROOT_TOKEN"
echo ""
echo "Cluster information:"
vault operator members

echo ""
echo "Next steps:"
echo "1. Unseal other Vault nodes using the same keys"
echo "2. Create policies: vault policy write <name> /vault/policies/<policy>.hcl"
echo "3. Create users: vault write auth/userpass/users/<username> password=<password> policies=<policy>"
echo "4. Configure auto-unseal for production use"
echo "5. Set up Consul ACLs for production security"