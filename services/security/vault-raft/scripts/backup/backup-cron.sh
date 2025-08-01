#!/bin/bash
# Automated backup wrapper for cron jobs
# Handles logging, retention, and error notification
# Supports hourly/daily backups with Google Drive integration

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
BACKUP_ROOT="${PROJECT_ROOT}/backups"
LOG_DIR="${PROJECT_ROOT}/logs"
LOG_FILE="${LOG_DIR}/backup-$(date +%Y%m).log"
CONFIG_FILE="${PROJECT_ROOT}/.gdrive-config"

# Backup type (hourly or daily)
BACKUP_TYPE="${1:-daily}"

# Retention settings based on backup type
if [ "$BACKUP_TYPE" = "hourly" ]; then
    # For hourly backups, keep only 24 hours locally
    RETENTION_DAYS=1
    RETENTION_COUNT=24
    LOG_FILE="${LOG_DIR}/backup-hourly-$(date +%Y%m%d).log"
else
    # For daily backups, use configured settings
    RETENTION_DAYS=${VAULT_BACKUP_RETENTION_DAYS:-30}
    RETENTION_COUNT=${VAULT_BACKUP_RETENTION_COUNT:-10}
fi

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Function to log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$BACKUP_TYPE] $1" | tee -a "$LOG_FILE"
}

# Function to handle errors
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Function to load Google Drive config
load_gdrive_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# Function to clean old backups
cleanup_old_backups() {
    log "Checking for old backups to clean up..."
    
    # Count current backups
    if [ -d "$BACKUP_ROOT" ]; then
        # For hourly backups, look for specific pattern
        if [ "$BACKUP_TYPE" = "hourly" ]; then
            # Remove hourly backups older than 24 hours
            find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" -mmin +1440 -exec rm -rf {} \; 2>/dev/null || true
            log "Removed hourly backups older than 24 hours"
        else
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
    fi
}

# Function to upload to Google Drive
upload_to_gdrive() {
    local backup_path="$1"
    
    # Load config
    load_gdrive_config
    
    # Check if Google Drive is enabled
    if [ "${GDRIVE_ENABLED:-false}" != "true" ]; then
        log "Google Drive backup is disabled"
        return 0
    fi
    
    # Check if this backup type is enabled for Google Drive
    if [ "$BACKUP_TYPE" = "hourly" ] && [ "${GDRIVE_HOURLY_ENABLED:-true}" != "true" ]; then
        log "Hourly Google Drive backup is disabled"
        return 0
    fi
    
    if [ "$BACKUP_TYPE" = "daily" ] && [ "${GDRIVE_DAILY_ENABLED:-true}" != "true" ]; then
        log "Daily Google Drive backup is disabled"
        return 0
    fi
    
    log "Uploading backup to Google Drive..."
    
    if "$PROJECT_ROOT/scripts/google/gdrive-upload.sh" "$backup_path" "$BACKUP_TYPE" >> "$LOG_FILE" 2>&1; then
        log "Successfully uploaded to Google Drive"
        return 0
    else
        log "WARNING: Failed to upload to Google Drive"
        return 1
    fi
}

# Main process
main() {
    log "=== Starting automated Vault backup ($BACKUP_TYPE) ==="
    
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
        # Try to read from vault_keys volume
        export VAULT_TOKEN=$(docker run --rm -v vault-raft_vault_keys:/keys:ro busybox cat /keys/root-token.txt 2>/dev/null || echo "")
        
        # Try alternative volume name if first attempt failed
        if [ -z "$VAULT_TOKEN" ]; then
            export VAULT_TOKEN=$(docker run --rm -v vault_vault_keys:/keys:ro busybox cat /keys/root-token.txt 2>/dev/null || echo "")
        fi
        
        if [ -n "$VAULT_TOKEN" ]; then
            log "Using root token from vault_keys volume"
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
                
                # Upload to Google Drive if enabled
                upload_to_gdrive "$latest_backup"
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
    log "Total local backups: $total_backups"
    log "Total local size: $total_size"
    log ""
}

# Lock file to prevent concurrent runs
LOCK_FILE="/tmp/vault-backup-${BACKUP_TYPE}.lock"

# Check if another backup is running
if [ -f "$LOCK_FILE" ]; then
    pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        log "Another $BACKUP_TYPE backup is already running (PID: $pid)"
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