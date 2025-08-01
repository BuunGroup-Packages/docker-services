ui = true
disable_mlock = true

storage "consul" {
  address = "consul-server-1:8500"
  path    = "vault/"
  
  # HA configuration
  ha_enabled = "true"
  
  # Service registration
  service = "vault"
  
  # Check timeout
  check_timeout = "5s"
  
  # Consistency mode
  consistency_mode = "strong"
  
  # Max parallel requests
  max_parallel = "128"
  
  # Session TTL
  session_ttl = "15s"
  
  # Lock wait time
  lock_wait_time = "15s"
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = 1
  # tls_cert_file = "/vault/tls/vault.crt"
  # tls_key_file  = "/vault/tls/vault.key"
}

# Internal cluster communication
listener "tcp" {
  address       = "0.0.0.0:8201"
  tls_disable   = 0
  tls_cert_file = "/vault/tls/vault.crt"
  tls_key_file  = "/vault/tls/vault.key"
}

# Service registration
service_registration "consul" {
  address = "consul-server-1:8500"
  service = "vault"
  
  # Additional service tags
  service_tags = "active"
  
  # Service address
  service_address = ""
  
  # Disable registration
  disable_registration = "false"
  
  # Check timeout
  check_timeout = "5s"
}

api_addr = "http://0.0.0.0:8200"
cluster_addr = "https://0.0.0.0:8201"

# Default TTLs
default_lease_ttl = "168h"
max_lease_ttl = "720h"

# Enable telemetry
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
  
  # StatsD integration (optional)
  # statsd_address = "statsd:8125"
  # statsite_address = "statsite:8125"
}

# Performance tuning
cache_size = 131072

# Plugin directory
plugin_directory = "/vault/plugins"

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