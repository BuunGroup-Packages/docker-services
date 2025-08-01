ui = true
disable_mlock = true

storage "raft" {
  path = "/vault/data"
  node_id = "VAULT_RAFT_NODE_ID_PLACEHOLDER"
  
  # Retry join configuration for clustering
  retry_join {
    leader_api_addr = "https://vault:8200"
    leader_ca_cert_file = "/vault/config/vault-ca.pem"
  }
  retry_join {
    leader_api_addr = "https://vault-2:8200"
    leader_ca_cert_file = "/vault/config/vault-ca.pem"
  }
  retry_join {
    leader_api_addr = "https://vault-3:8200"
    leader_ca_cert_file = "/vault/config/vault-ca.pem"
  }
}

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/config/vault.pem"
  tls_key_file  = "/vault/config/vault-key.pem"
  tls_client_ca_file = "/vault/config/vault-ca.pem"
  tls_require_and_verify_client_cert = false
  tls_disable_client_certs = false
}

# Internal cluster communication
listener "tcp" {
  address       = "0.0.0.0:8201"
  tls_cert_file = "/vault/config/vault.pem"
  tls_key_file  = "/vault/config/vault-key.pem"
  tls_client_ca_file = "/vault/config/vault-ca.pem"
  tls_require_and_verify_client_cert = true
  tls_disable_client_certs = false
}

api_addr = "https://0.0.0.0:8200"
cluster_addr = "https://0.0.0.0:8201"

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

# Auto-unseal options remain the same as vault.hcl