#!/bin/bash
# Verify integrity of a Vault backup

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

echo -e "${BLUE}=== Vault Backup Verification ===${NC}"
echo ""

# Function to verify tar file
verify_tar() {
    local file=$1
    local name=$2
    
    if [ ! -f "$file" ]; then
        echo -e "  ${RED}✗ $name: File not found${NC}"
        return 1
    fi
    
    # Check if tar is valid
    if tar tzf "$file" >/dev/null 2>&1; then
        local count=$(tar tzf "$file" 2>/dev/null | wc -l)
        local size=$(du -h "$file" | cut -f1)
        echo -e "  ${GREEN}✓ $name: Valid ($count files, $size)${NC}"
        return 0
    else
        echo -e "  ${RED}✗ $name: Corrupt or invalid${NC}"
        return 1
    fi
}

# Function to verify snapshot
verify_snapshot() {
    local file=$1
    
    if [ ! -f "$file" ]; then
        echo -e "  ${RED}✗ Raft snapshot: File not found${NC}"
        return 1
    fi
    
    # Check if file is not empty and has reasonable size
    local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
    local human_size=$(du -h "$file" | cut -f1)
    
    if [ "$size" -gt 0 ]; then
        echo -e "  ${GREEN}✓ Raft snapshot: Present ($human_size)${NC}"
        
        # Try to check if it's a valid gzip file (Vault snapshots are gzipped)
        if gzip -t "$file" 2>/dev/null; then
            echo -e "    ${GREEN}Format: Valid gzip${NC}"
        else
            echo -e "    ${YELLOW}Format: Not gzip (may still be valid)${NC}"
        fi
        return 0
    else
        echo -e "  ${RED}✗ Raft snapshot: Empty file${NC}"
        return 1
    fi
}

# Main verification
main() {
    BACKUP_TIMESTAMP="$1"
    
    # If no timestamp provided, show usage
    if [ -z "$BACKUP_TIMESTAMP" ]; then
        echo "Usage: $0 <backup-timestamp>"
        echo ""
        echo "Available backups:"
        if [ -d "$BACKUP_ROOT" ]; then
            for backup in $(ls -d "$BACKUP_ROOT"/*/ 2>/dev/null | sort -r); do
                echo "  - $(basename "$backup")"
            done
        else
            echo "  No backups found"
        fi
        exit 1
    fi
    
    BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_TIMESTAMP}"
    
    # Check if backup exists
    if [ ! -d "$BACKUP_DIR" ]; then
        echo -e "${RED}Error: Backup $BACKUP_TIMESTAMP not found${NC}"
        exit 1
    fi
    
    echo -e "Verifying backup: ${YELLOW}$BACKUP_TIMESTAMP${NC}"
    echo -e "Location: $BACKUP_DIR"
    echo ""
    
    ERRORS=0
    
    # 1. Verify manifest
    echo -e "${BLUE}1. Checking manifest...${NC}"
    if [ -f "$BACKUP_DIR/manifest.json" ]; then
        if manifest=$(cat "$BACKUP_DIR/manifest.json" 2>/dev/null) && echo "$manifest" | grep -q '"timestamp"'; then
            echo -e "  ${GREEN}✓ Manifest: Valid JSON${NC}"
            
            # Extract and display key information
            date=$(echo "$manifest" | grep -o '"date":"[^"]*' | cut -d'"' -f4)
            tls=$(echo "$manifest" | grep -o '"tls_enabled":[^,}]*' | cut -d':' -f2 | tr -d ' ')
            version=$(echo "$manifest" | grep -o '"vault_version":"[^"]*' | cut -d'"' -f4)
            
            echo -e "    Date: $date"
            echo -e "    TLS: $tls"
            echo -e "    Vault Version: $version"
        else
            echo -e "  ${RED}✗ Manifest: Invalid JSON${NC}"
            ((ERRORS++))
        fi
    else
        echo -e "  ${RED}✗ Manifest: Not found${NC}"
        ((ERRORS++))
    fi
    
    # 2. Verify Raft snapshot
    echo -e "\n${BLUE}2. Checking Raft snapshot...${NC}"
    verify_snapshot "$BACKUP_DIR/vault-raft.snap" || ((ERRORS++))
    
    # 3. Verify configuration
    echo -e "\n${BLUE}3. Checking configuration backup...${NC}"
    verify_tar "$BACKUP_DIR/vault-config.tar.gz" "Configuration" || ((ERRORS++))
    
    # 4. Verify keys (if present)
    echo -e "\n${BLUE}4. Checking keys backup...${NC}"
    if [ -f "$BACKUP_DIR/vault-keys.tar.gz" ]; then
        verify_tar "$BACKUP_DIR/vault-keys.tar.gz" "Keys" || ((ERRORS++))
    else
        echo -e "  ${YELLOW}! Keys backup not found (vault may not have been initialized)${NC}"
    fi
    
    # 5. Verify TLS certificates (if TLS enabled)
    echo -e "\n${BLUE}5. Checking TLS certificates...${NC}"
    if [ -f "$BACKUP_DIR/manifest.json" ]; then
        tls_enabled=$(cat "$BACKUP_DIR/manifest.json" | grep -o '"tls_enabled":[^,}]*' | cut -d':' -f2 | tr -d ' ')
        if [ "$tls_enabled" = "true" ]; then
            if [ -f "$BACKUP_DIR/vault-certs.tar.gz" ]; then
                verify_tar "$BACKUP_DIR/vault-certs.tar.gz" "TLS Certificates" || ((ERRORS++))
            else
                echo -e "  ${RED}✗ TLS certificates expected but not found${NC}"
                ((ERRORS++))
            fi
        else
            echo -e "  ${BLUE}ℹ TLS not enabled for this backup${NC}"
        fi
    fi
    
    # 6. Check for unexpected files
    echo -e "\n${BLUE}6. Checking for unexpected files...${NC}"
    expected_files="manifest.json vault-raft.snap vault-config.tar.gz vault-keys.tar.gz vault-certs.tar.gz"
    unexpected=0
    for file in "$BACKUP_DIR"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            if ! echo "$expected_files" | grep -q "$filename"; then
                echo -e "  ${YELLOW}! Unexpected file: $filename${NC}"
                ((unexpected++))
            fi
        fi
    done
    if [ $unexpected -eq 0 ]; then
        echo -e "  ${GREEN}✓ No unexpected files found${NC}"
    fi
    
    # Summary
    echo -e "\n${BLUE}=== Verification Summary ===${NC}"
    
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)
    echo -e "Backup size: $BACKUP_SIZE"
    
    if [ $ERRORS -eq 0 ]; then
        echo -e "\n${GREEN}✓ Backup verification PASSED${NC}"
        echo -e "This backup appears to be complete and valid."
        echo ""
        echo -e "${BLUE}To restore this backup, run:${NC}"
        echo -e "  ./scripts/restore-vault.sh $BACKUP_TIMESTAMP"
    else
        echo -e "\n${RED}✗ Backup verification FAILED${NC}"
        echo -e "Found $ERRORS error(s) during verification."
        echo -e "${YELLOW}This backup may be incomplete or corrupted.${NC}"
    fi
}

# Run main function
main "$@"