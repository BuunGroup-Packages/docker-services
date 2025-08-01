# CI/CD Pipeline Policy - For automated deployment pipelines
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