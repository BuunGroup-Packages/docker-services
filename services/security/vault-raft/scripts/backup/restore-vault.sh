#!/bin/bash
# Vault Restore Script
# Restores Vault from a backup created by backup-vault.sh
# Handles both TLS and non-TLS configurations

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_ROOT="${PROJECT_ROOT}/backups"

echo -e "${BLUE}=== Vault Restore Script ===${NC}"
echo ""

# Function to list available backups
list_backups() {
    if [ ! -d "$BACKUP_ROOT" ] || [ -z "$(ls -A "$BACKUP_ROOT" 2>/dev/null)" ]; then
        echo -e "${RED}No backups found in $BACKUP_ROOT${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Available backups:${NC}"
    echo ""
    
    for backup in $(ls -d "$BACKUP_ROOT"/*/ 2>/dev/null | sort -r); do
        backup_name=$(basename "$backup")
        if [ -f "$backup/manifest.json" ]; then
            manifest=$(cat "$backup/manifest.json")
            date=$(echo "$manifest" | grep -o '"date":"[^"]*' | cut -d'"' -f4)
            size=$(echo "$manifest" | grep -o '"backup_size":"[^"]*' | cut -d'"' -f4)
            tls=$(echo "$manifest" | grep -o '"tls_enabled":[^,}]*' | cut -d':' -f2 | tr -d ' ')
            
            echo -e "  ${GREEN}$backup_name${NC}"
            echo -e "    Date: $date"
            echo -e "    Size: $size"
            echo -e "    TLS: $tls"
            echo ""
        fi
    done
}

# Function to validate backup
validate_backup() {
    local backup_dir="$1"
    
    if [ ! -f "$backup_dir/manifest.json" ]; then
        echo -e "${RED}Error: Invalid backup - manifest.json not found${NC}"
        return 1
    fi
    
    if [ ! -f "$backup_dir/vault-raft.snap" ]; then
        echo -e "${RED}Error: Invalid backup - vault-raft.snap not found${NC}"
        return 1
    fi
    
    if [ ! -f "$backup_dir/vault-config.tar.gz" ]; then
        echo -e "${RED}Error: Invalid backup - vault-config.tar.gz not found${NC}"
        return 1
    fi
    
    return 0
}

# Function to prompt for confirmation
confirm() {
    local prompt="$1"
    local response
    
    echo -e "${YELLOW}$prompt${NC}"
    read -p "Type 'yes' to continue: " response
    
    if [ "$response" != "yes" ]; then
        echo -e "${RED}Restore cancelled${NC}"
        exit 1
    fi
}

# Function to stop vault if running
stop_vault() {
    if docker ps --format '{{.Names}}' | grep -q "^vault"; then
        echo -e "${YELLOW}Stopping existing Vault containers...${NC}"
        cd "$PROJECT_ROOT"
        ./scripts/cleanup.sh
    fi
}

# Main restore process
main() {
    # Parse arguments
    BACKUP_TIMESTAMP="$1"
    
    # If no timestamp provided, list backups and ask
    if [ -z "$BACKUP_TIMESTAMP" ]; then
        list_backups
        read -p "Enter backup timestamp to restore: " BACKUP_TIMESTAMP
    fi
    
    BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_TIMESTAMP}"
    
    # Validate backup exists
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}Error: Backup $BACKUP_TIMESTAMP not found${NC}"
        exit 1
    fi
    
    # Validate backup contents
    if ! validate_backup "$BACKUP_DIR"; then
        exit 1
    fi
    
    # Read manifest
    MANIFEST=$(cat "$BACKUP_DIR/manifest.json")
    TLS_ENABLED=$(echo "$MANIFEST" | grep -o '"tls_enabled":[^,}]*' | cut -d':' -f2 | tr -d ' ')
    BACKUP_DATE=$(echo "$MANIFEST" | grep -o '"date":"[^"]*' | cut -d'"' -f4)
    
    echo -e "\n${BLUE}Backup Information:${NC}"
    echo -e "  Timestamp: $BACKUP_TIMESTAMP"
    echo -e "  Date: $BACKUP_DATE"
    echo -e "  TLS Enabled: $TLS_ENABLED"
    echo ""
    
    # Confirm restoration
    confirm "WARNING: This will replace ALL current Vault data! Are you sure?"
    
    # Stop existing Vault
    stop_vault
    
    echo -e "\n${BLUE}Starting restoration...${NC}"
    
    # 1. Restore configuration
    echo -e "\n${YELLOW}1. Restoring configuration...${NC}"
    cd "$PROJECT_ROOT"
    
    # Backup current config (just in case)
    if [ -d "config" ] || [ -d "policies" ]; then
        echo "  Backing up current configuration..."
        mkdir -p "${BACKUP_ROOT}/pre-restore-${BACKUP_TIMESTAMP}"
        tar czf "${BACKUP_ROOT}/pre-restore-${BACKUP_TIMESTAMP}/current-config.tar.gz" \
            config/ policies/ scripts/ docker-compose*.yml .env* 2>/dev/null || true
    fi
    
    # Extract configuration
    tar xzf "$BACKUP_DIR/vault-config.tar.gz"
    echo -e "${GREEN}✓ Configuration restored${NC}"
    
    # 2. Restore TLS certificates (if present)
    if [ "$TLS_ENABLED" = "true" ] && [ -f "$BACKUP_DIR/vault-certs.tar.gz" ]; then
        echo -e "\n${YELLOW}2. Restoring TLS certificates...${NC}"
        tar xzf "$BACKUP_DIR/vault-certs.tar.gz"
        echo -e "${GREEN}✓ TLS certificates restored${NC}"
    elif [ "$TLS_ENABLED" = "true" ]; then
        echo -e "${YELLOW}Warning: Backup has TLS enabled but no certificates found${NC}"
    fi
    
    # 3. Start Vault
    echo -e "\n${YELLOW}3. Starting Vault...${NC}"
    if [ "$TLS_ENABLED" = "true" ]; then
        ./scripts/start.sh --tls --no-init
    else
        ./scripts/start.sh --no-init
    fi
    
    # Wait for Vault to be ready
    echo "  Waiting for Vault to start..."
    sleep 10
    
    # 4. Restore keys
    if [ -f "$BACKUP_DIR/vault-keys.tar.gz" ]; then
        echo -e "\n${YELLOW}4. Restoring initialization keys...${NC}"
        docker run --rm \
            -v vault-raft_vault_keys:/keys \
            -v "$BACKUP_DIR":/backup:ro \
            busybox tar xzf /backup/vault-keys.tar.gz -C /keys
        echo -e "${GREEN}✓ Keys restored${NC}"
    fi
    
    # 5. Restore Raft snapshot
    echo -e "\n${YELLOW}5. Restoring Raft snapshot...${NC}"
    
    # Copy snapshot to container
    docker cp "$BACKUP_DIR/vault-raft.snap" vault:/tmp/restore.snap
    
    # Get root token
    ROOT_TOKEN=""
    
    # Try to read from vault_keys volume
    echo "  Retrieving root token..."
    ROOT_TOKEN=$(docker run --rm -v vault-raft_vault_keys:/keys:ro busybox cat /keys/root-token.txt 2>/dev/null || echo "")
    
    # Try alternative volume name if first attempt failed
    if [ -z "$ROOT_TOKEN" ]; then
        ROOT_TOKEN=$(docker run --rm -v vault_vault_keys:/keys:ro busybox cat /keys/root-token.txt 2>/dev/null || echo "")
    fi
    
    if [ -z "$ROOT_TOKEN" ] && [ -z "$VAULT_TOKEN" ]; then
        echo -e "${YELLOW}No root token found. Please provide it:${NC}"
        read -s -p "Root Token: " ROOT_TOKEN
        echo ""
    fi
    
    # Perform restore
    if [ -n "$ROOT_TOKEN" ]; then
        docker exec -e VAULT_TOKEN="$ROOT_TOKEN" vault vault operator raft snapshot restore -force /tmp/restore.snap
    elif [ -n "$VAULT_TOKEN" ]; then
        docker exec -e VAULT_TOKEN="$VAULT_TOKEN" vault vault operator raft snapshot restore -force /tmp/restore.snap
    else
        echo -e "${RED}Error: No root token available for restore${NC}"
        exit 1
    fi
    
    # Clean up
    docker exec vault rm -f /tmp/restore.snap
    echo -e "${GREEN}✓ Raft snapshot restored${NC}"
    
    # 6. Restart Vault to ensure clean state
    echo -e "\n${YELLOW}6. Restarting Vault...${NC}"
    docker restart vault
    sleep 5
    
    # 7. Unseal Vault
    echo -e "\n${YELLOW}7. Unsealing Vault...${NC}"
    echo -e "Vault needs to be unsealed with 3 keys."
    
    # Try to auto-unseal if we have the keys
    if docker exec vault test -f /vault/keys/unseal-keys.txt 2>/dev/null; then
        echo "  Found unseal keys, attempting automatic unseal..."
        for i in 1 2 3; do
            KEY=$(docker exec vault sed -n "${i}p" /vault/keys/unseal-keys.txt 2>/dev/null)
            if [ -n "$KEY" ]; then
                docker exec vault vault operator unseal "$KEY" >/dev/null 2>&1
                echo -e "  ${GREEN}✓ Applied unseal key $i${NC}"
            fi
        done
    else
        echo "  Please enter unseal keys manually:"
        for i in 1 2 3; do
            docker exec -it vault vault operator unseal
        done
    fi
    
    # Check final status
    echo -e "\n${BLUE}Checking Vault status...${NC}"
    docker exec vault vault status || true
    
    # Display summary
    echo -e "\n${GREEN}=== Restore Complete ===${NC}"
    echo ""
    echo "Vault has been restored from backup: $BACKUP_TIMESTAMP"
    echo ""
    
    if [ -n "$ROOT_TOKEN" ]; then
        echo -e "Root Token: ${ROOT_TOKEN}"
    elif docker exec vault test -f /vault/keys/root-token.txt 2>/dev/null; then
        ROOT_TOKEN=$(docker exec vault cat /vault/keys/root-token.txt 2>/dev/null || echo "")
        [ -n "$ROOT_TOKEN" ] && echo -e "Root Token: ${ROOT_TOKEN}"
    fi
    
    echo ""
    echo -e "${BLUE}Access Vault at:${NC}"
    if [ "$TLS_ENABLED" = "true" ]; then
        echo "  https://localhost:8200"
        echo ""
        echo "  export VAULT_ADDR='https://localhost:8200'"
        echo "  export VAULT_CACERT=\$PWD/certs/vault-ca.pem"
    else
        echo "  http://localhost:8200"
        echo ""
        echo "  export VAULT_ADDR='http://localhost:8200'"
    fi
}

# Run main function
main "$@"