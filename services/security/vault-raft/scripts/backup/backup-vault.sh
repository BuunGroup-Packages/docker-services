#!/bin/bash
# Vault Backup Script
# Creates complete backups of Vault including Raft data, keys, config, and certificates
# Works with both TLS and non-TLS configurations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BACKUP_ROOT="/var/log/vault-backup"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"

# Ensure backup directory exists
if [ ! -d "$BACKUP_ROOT" ]; then
    if command -v sudo >/dev/null 2>&1; then
        echo -e "${YELLOW}Creating backup directory with sudo...${NC}"
        sudo mkdir -p "$BACKUP_ROOT"
        sudo chmod 777 "$BACKUP_ROOT"
    else
        echo -e "${RED}Error: Cannot create $BACKUP_ROOT (permission denied)${NC}"
        echo -e "${RED}Please run: sudo mkdir -p $BACKUP_ROOT && sudo chmod 777 $BACKUP_ROOT${NC}"
        exit 1
    fi
fi
mkdir -p "$BACKUP_DIR"

echo -e "${BLUE}=== Vault Backup Script ===${NC}"
echo -e "Backup directory: ${BACKUP_DIR}"
echo ""

# Function to check if container is running
check_container() {
    if ! docker ps --format '{{.Names}}' | grep -q "^vault$"; then
        echo -e "${RED}Error: Vault container is not running${NC}"
        exit 1
    fi
}

# Function to detect TLS mode
detect_tls() {
    if [ -d "${PROJECT_ROOT}/certs" ] && [ "$(ls -A ${PROJECT_ROOT}/certs 2>/dev/null)" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to get Vault status
get_vault_status() {
    local vault_status=$(docker exec vault vault status -format=json 2>/dev/null || echo "{}")
    echo "$vault_status"
}

# Main backup process
main() {
    echo -e "${YELLOW}Starting Vault backup...${NC}"
    
    # Check if Vault is running
    check_container
    
    # Detect TLS mode
    TLS_MODE=$(detect_tls)
    echo -e "TLS Mode: ${TLS_MODE}"
    
    # Get Vault status
    VAULT_STATUS=$(get_vault_status)
    SEALED=$(echo "$VAULT_STATUS" | grep -o '"sealed":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    
    if [ "$SEALED" = "true" ]; then
        echo -e "${YELLOW}Warning: Vault is sealed. Backup will proceed but may be incomplete.${NC}"
    fi
    
    # Create manifest
    echo -e "\n${BLUE}Creating backup manifest...${NC}"
    cat > "${BACKUP_DIR}/manifest.json" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "date": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")",
  "tls_enabled": ${TLS_MODE},
  "vault_sealed": ${SEALED:-true},
  "vault_version": "$(docker exec vault vault version 2>/dev/null || echo "unknown")",
  "backup_version": "1.0"
}
EOF
    
    # 1. Backup Raft snapshot
    echo -e "\n${BLUE}1. Taking Raft snapshot...${NC}"
    
    # Check if we need to use VAULT_TOKEN
    if [ -n "$VAULT_TOKEN" ]; then
        docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault operator raft snapshot save /tmp/vault-backup.snap
    else
        # Try to read token from vault_keys volume
        echo -e "  Retrieving root token from secure storage..."
        ROOT_TOKEN=$(docker run --rm -v vault-raft_vault_keys:/keys:ro busybox cat /keys/root-token.txt 2>/dev/null || echo "")
        
        if [ -n "$ROOT_TOKEN" ]; then
            echo -e "  ${GREEN}✓ Root token retrieved${NC}"
            docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault vault operator raft snapshot save /tmp/vault-backup.snap
        else
            # Try alternative volume name (in case of different project name)
            ROOT_TOKEN=$(docker run --rm -v vault_vault_keys:/keys:ro busybox cat /keys/root-token.txt 2>/dev/null || echo "")
            if [ -n "$ROOT_TOKEN" ]; then
                echo -e "  ${GREEN}✓ Root token retrieved${NC}"
                docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault vault operator raft snapshot save /tmp/vault-backup.snap
            else
                echo -e "${YELLOW}Warning: No root token found in vault_keys volume${NC}"
                echo -e "${YELLOW}Attempting snapshot without authentication...${NC}"
                docker exec vault vault operator raft snapshot save /tmp/vault-backup.snap
            fi
        fi
    fi
    
    # Copy snapshot from container
    docker cp vault:/tmp/vault-backup.snap "${BACKUP_DIR}/vault-raft.snap"
    docker exec vault rm -f /tmp/vault-backup.snap
    echo -e "${GREEN}✓ Raft snapshot saved${NC}"
    
    # 2. Backup initialization keys
    echo -e "\n${BLUE}2. Backing up initialization keys...${NC}"
    if docker volume ls --format '{{.Name}}' | grep -q '^vault-raft_vault_keys$'; then
        docker run --rm \
            -v vault-raft_vault_keys:/keys:ro \
            -v "${BACKUP_DIR}":/backup \
            busybox tar czf /backup/vault-keys.tar.gz -C /keys .
        echo -e "${GREEN}✓ Keys backed up${NC}"
    else
        echo -e "${YELLOW}! Keys volume not found (may not be initialized yet)${NC}"
    fi
    
    # 3. Backup configuration
    echo -e "\n${BLUE}3. Backing up configuration...${NC}"
    cd "$PROJECT_ROOT"
    tar czf "${BACKUP_DIR}/vault-config.tar.gz" \
        config/ \
        policies/ \
        scripts/ \
        docker-compose*.yml \
        .env* \
        README.md \
        2>/dev/null || true
    echo -e "${GREEN}✓ Configuration backed up${NC}"
    
    # 4. Backup TLS certificates (if present)
    if [ "$TLS_MODE" = "true" ]; then
        echo -e "\n${BLUE}4. Backing up TLS certificates...${NC}"
        # Backup from Docker volume which has all certificates
        if docker volume ls --format '{{.Name}}' | grep -q '^vault-raft_vault_certs$'; then
            docker run --rm \
                -v vault-raft_vault_certs:/certs:ro \
                -v "${BACKUP_DIR}":/backup \
                busybox tar czf /backup/vault-certs.tar.gz -C /certs .
            echo -e "${GREEN}✓ TLS certificates backed up from volume${NC}"
        else
            echo -e "${YELLOW}! Certificate volume not found${NC}"
        fi
    fi
    
    # 5. Calculate backup size
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
    
    # Update manifest with final info
    cat > "${BACKUP_DIR}/manifest.json" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "date": "$(date -u +"%Y-%m-%d %H:%M:%S UTC")",
  "tls_enabled": ${TLS_MODE},
  "vault_sealed": ${SEALED:-true},
  "vault_version": "$(docker exec vault vault version 2>/dev/null || echo "unknown")",
  "backup_version": "1.0",
  "backup_size": "${BACKUP_SIZE}",
  "files": {
    "raft_snapshot": "vault-raft.snap",
    "keys": "vault-keys.tar.gz",
    "config": "vault-config.tar.gz",
    "certs": $([ "$TLS_MODE" = "true" ] && echo '"vault-certs.tar.gz"' || echo "null")
  }
}
EOF
    
    # Summary
    echo -e "\n${GREEN}=== Backup Complete ===${NC}"
    echo -e "Location: ${BACKUP_DIR}"
    echo -e "Size: ${BACKUP_SIZE}"
    echo -e "Files:"
    ls -la "$BACKUP_DIR"
    
    echo -e "\n${YELLOW}Important: Store this backup securely!${NC}"
    echo -e "The backup contains sensitive data including:"
    echo -e "  - All Vault secrets and configuration"
    echo -e "  - Initialization/unseal keys"
    [ "$TLS_MODE" = "true" ] && echo -e "  - TLS private keys"
    
    echo -e "\n${BLUE}To restore this backup, run:${NC}"
    echo -e "  ./scripts/backup/restore-vault.sh ${TIMESTAMP}"
}

# Run main function
main "$@"