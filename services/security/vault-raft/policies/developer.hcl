# Developer Policy - Access to dev resources and personal namespaces
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