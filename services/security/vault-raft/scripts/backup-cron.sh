#!/bin/bash
# Automated backup wrapper for cron jobs
# Handles logging, retention, and error notification

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_ROOT="${PROJECT_ROOT}/backups"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/backup-$(date +%Y%m).log"

# Retention settings (customize as needed)
RETENTION_DAYS=${VAULT_BACKUP_RETENTION_DAYS:-30}
RETENTION_COUNT=${VAULT_BACKUP_RETENTION_COUNT:-10}

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to handle errors
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Function to clean old backups
cleanup_old_backups() {
    log "Checking for old backups to clean up..."
    
    # Count current backups
    if [ -d "$BACKUP_ROOT" ]; then
        current_count=$(ls -d "$BACKUP_ROOT"/*/ 2>/dev/null | wc -l)
        log "Current backup count: $current_count"
        
        # Remove by age (older than RETENTION_DAYS)
        if [ "$RETENTION_DAYS" -gt 0 ]; then
            find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true
            log "Removed backups older than $RETENTION_DAYS days"
        fi
        
        # Remove by count (keep only RETENTION_COUNT most recent)
        if [ "$RETENTION_COUNT" -gt 0 ] && [ "$current_count" -gt "$RETENTION_COUNT" ]; then
            # Get list of backups sorted by date (oldest first)
            backups_to_remove=$(ls -d "$BACKUP_ROOT"/*/ 2>/dev/null | sort | head -n -$RETENTION_COUNT)
            for backup in $backups_to_remove; do
                log "Removing old backup: $(basename "$backup")"
                rm -rf "$backup"
            done
        fi
    fi
}

# Main process
main() {
    log "=== Starting automated Vault backup ==="
    
    # Check if Vault is running
    if ! docker ps --format '{{.Names}}' | grep -q "^vault$"; then
        error_exit "Vault container is not running"
    fi
    
    # Check if Vault is sealed
    sealed=$(docker exec vault vault status -format=json 2>/dev/null | grep -o '"sealed":[^,}]*' | cut -d':' -f2 | tr -d ' ' || echo "true")
    if [ "$sealed" = "true" ]; then
        log "WARNING: Vault is sealed. Backup may be incomplete."
    fi
    
    # Get root token if available
    if [ -z "$VAULT_TOKEN" ]; then
        if docker exec vault test -f /vault/keys/root-token.txt 2>/dev/null; then
            export VAULT_TOKEN=$(docker exec vault cat /vault/keys/root-token.txt 2>/dev/null || echo "")
            log "Using root token from container"
        else
            log "WARNING: No root token available. Backup may fail."
        fi
    fi
    
    # Run the backup
    log "Executing backup script..."
    if "$SCRIPT_DIR/backup-vault.sh" >> "$LOG_FILE" 2>&1; then
        log "Backup completed successfully"
        
        # Get the latest backup timestamp
        latest_backup=$(ls -d "$BACKUP_ROOT"/*/ 2>/dev/null | sort -r | head -1)
        if [ -n "$latest_backup" ]; then
            backup_name=$(basename "$latest_backup")
            backup_size=$(du -sh "$latest_backup" | cut -f1)
            log "Created backup: $backup_name (size: $backup_size)"
            
            # Verify the backup
            log "Verifying backup..."
            if "$SCRIPT_DIR/verify-backup.sh" "$backup_name" >> "$LOG_FILE" 2>&1; then
                log "Backup verification passed"
            else
                log "WARNING: Backup verification failed"
            fi
        fi
    else
        error_exit "Backup script failed"
    fi
    
    # Clean up old backups
    cleanup_old_backups
    
    # Report final status
    total_backups=$(ls -d "$BACKUP_ROOT"/*/ 2>/dev/null | wc -l || echo "0")
    total_size=$(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1 || echo "0")
    
    log "=== Backup job completed ==="
    log "Total backups: $total_backups"
    log "Total size: $total_size"
    log ""
}

# Lock file to prevent concurrent runs
LOCK_FILE="/tmp/vault-backup.lock"

# Check if another backup is running
if [ -f "$LOCK_FILE" ]; then
    pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        log "Another backup is already running (PID: $pid)"
        exit 0
    else
        log "Removing stale lock file"
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock file
echo $$ > "$LOCK_FILE"

# Ensure lock file is removed on exit
trap "rm -f $LOCK_FILE" EXIT

# Run main process
main "$@"