#!/bin/bash
# List all available Vault backups with details

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BACKUP_ROOT="/var/log/vault-backup"

echo -e "${BLUE}=== Vault Backup List ===${NC}"
echo ""

# Check if backup directory exists
if [ ! -d "$BACKUP_ROOT" ]; then
    echo -e "${YELLOW}No backup directory found at: $BACKUP_ROOT${NC}"
    echo "Run ./scripts/backup-vault.sh to create your first backup"
    exit 0
fi

# Check if any backups exist
if [ -z "$(ls -A "$BACKUP_ROOT" 2>/dev/null)" ]; then
    echo -e "${YELLOW}No backups found${NC}"
    echo "Run ./scripts/backup-vault.sh to create your first backup"
    exit 0
fi

# Function to format size
format_size() {
    local size=$1
    if [ -z "$size" ]; then
        echo "unknown"
    else
        echo "$size"
    fi
}

# Function to check backup validity
check_backup_validity() {
    local backup_dir=$1
    local valid=true
    local missing=""
    
    [ ! -f "$backup_dir/manifest.json" ] && missing="$missing manifest.json"
    [ ! -f "$backup_dir/vault-raft.snap" ] && missing="$missing vault-raft.snap"
    [ ! -f "$backup_dir/vault-config.tar.gz" ] && missing="$missing vault-config.tar.gz"
    
    if [ -n "$missing" ]; then
        echo -e "${RED}Invalid${NC} (missing:$missing)"
    else
        echo -e "${GREEN}Valid${NC}"
    fi
}

# Count total backups
TOTAL_BACKUPS=$(ls -d "$BACKUP_ROOT"/*/ 2>/dev/null | wc -l)
TOTAL_SIZE=$(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1)

echo -e "Location: ${BACKUP_ROOT}"
echo -e "Total backups: ${TOTAL_BACKUPS}"
echo -e "Total size: ${TOTAL_SIZE}"
echo ""

# List backups sorted by date (newest first)
echo -e "${CYAN}Timestamp            Date                          Size     TLS    Status${NC}"
echo -e "────────────────────────────────────────────────────────────────────────"

for backup in $(ls -d "$BACKUP_ROOT"/*/ 2>/dev/null | sort -r); do
    backup_name=$(basename "$backup")
    
    # Default values
    date="Unknown"
    size="Unknown"
    tls="Unknown"
    vault_version="Unknown"
    
    # Read manifest if exists
    if [ -f "$backup/manifest.json" ]; then
        manifest=$(cat "$backup/manifest.json" 2>/dev/null || echo "{}")
        date=$(echo "$manifest" | grep -o '"date":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
        size=$(echo "$manifest" | grep -o '"backup_size":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
        tls=$(echo "$manifest" | grep -o '"tls_enabled":[^,}]*' | cut -d':' -f2 | tr -d ' ' || echo "Unknown")
        vault_version=$(echo "$manifest" | grep -o '"vault_version":"[^"]*' | cut -d'"' -f4 || echo "Unknown")
        
        # Format TLS status
        if [ "$tls" = "true" ]; then
            tls="${GREEN}Yes${NC}"
        elif [ "$tls" = "false" ]; then
            tls="No "
        fi
    fi
    
    # Check validity
    status=$(check_backup_validity "$backup")
    
    # Format output
    printf "%-20s %-29s %-8s %-6s %s\n" \
        "$backup_name" \
        "$date" \
        "$size" \
        "$tls" \
        "$status"
done

echo ""

# Show most recent backup details
LATEST_BACKUP=$(ls -d "$BACKUP_ROOT"/*/ 2>/dev/null | sort -r | head -1)
if [ -n "$LATEST_BACKUP" ] && [ -f "$LATEST_BACKUP/manifest.json" ]; then
    echo -e "${BLUE}Latest backup details:${NC}"
    backup_name=$(basename "$LATEST_BACKUP")
    manifest=$(cat "$LATEST_BACKUP/manifest.json")
    
    echo -e "  Timestamp: ${backup_name}"
    echo -e "  Contents:"
    
    # List files in backup
    for file in "$LATEST_BACKUP"/*; do
        if [ -f "$file" ]; then
            filename=$(basename "$file")
            filesize=$(du -h "$file" | cut -f1)
            echo -e "    - $filename ($filesize)"
        fi
    done
    
    echo ""
    echo -e "${YELLOW}To restore a backup, run:${NC}"
    echo -e "  ./scripts/restore-vault.sh ${backup_name}"
fi