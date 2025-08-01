# Auditor Policy - Read-only access for compliance and auditing
# Read access to all secrets metadata
path "secret/metadata/*" {
  capabilities = ["read", "list"]
}

# View audit logs configuration
path "sys/audit" {
  capabilities = ["read", "list"]
}

# View all policies
path "sys/policies/*" {
  capabilities = ["read", "list"]
}

# View all auth methods
path "sys/auth" {
  capabilities = ["read", "list"]
}

# View all mounts
path "sys/mounts" {
  capabilities = ["read", "list"]
}

# Cannot read actual secret values
path "secret/data/*" {
  capabilities = ["deny"]
}