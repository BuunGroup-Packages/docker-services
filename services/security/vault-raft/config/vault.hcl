ui = true
disable_mlock = true

storage "raft" {
  path = "/vault/data"
  node_id = "VAULT_RAFT_NODE_ID_PLACEHOLDER"
  
  # Retry join configuration for clustering
  retry_join {
    leader_api_addr = "http://vault:8200"
  }
  retry_join {
    leader_api_addr = "http://vault-2:8200"
  }
  retry_join {
    leader_api_addr = "http://vault-3:8200"
  }
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = 1
  # tls_cert_file = "/vault/config/vault.crt"
  # tls_key_file  = "/vault/config/vault.key"
}

# Internal cluster communication
listener "tcp" {
  address       = "0.0.0.0:8201"
  tls_disable   = 1
}

api_addr = "http://0.0.0.0:8200"
cluster_addr = "http://0.0.0.0:8201"

# Default TTLs
default_lease_ttl = "168h"
max_lease_ttl = "720h"

# Enable telemetry
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}

# Performance tuning
performance_multiplier = 1

# Logging
log_level = "info"
log_format = "json"

# Audit logging
# audit {
#   type = "file"
#   options = {
#     file_path = "/vault/logs/audit.log"
#     mode = "0600"
#     format = "json"
#   }
# }

# Auto-unseal using AWS KMS (optional)
# seal "awskms" {
#   region     = "us-east-1"
#   kms_key_id = "your-kms-key-id"
# }

# Auto-unseal using Azure Key Vault (optional)
# seal "azurekeyvault" {
#   tenant_id      = "your-tenant-id"
#   client_id      = "your-client-id"
#   client_secret  = "your-client-secret"
#   vault_name     = "your-vault-name"
#   key_name       = "your-key-name"
# }

# Auto-unseal using GCP KMS (optional)
# seal "gcpckms" {
#   project     = "your-project"
#   region      = "us-east1"
#   key_ring    = "your-keyring"
#   crypto_key  = "your-key"
# }

# Auto-unseal using Transit (for development/testing)
# seal "transit" {
#   address = "http://vault-transit:8200"
#   disable_renewal = "false"
#   key_name = "autounseal"
#   mount_path = "transit/"
#   tls_skip_verify = "true"
# }