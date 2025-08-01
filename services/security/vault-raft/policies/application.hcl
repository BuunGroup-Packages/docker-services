# Application Policy - For services and applications
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