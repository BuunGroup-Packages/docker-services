#!/bin/bash
# Simple cron setup for Vault backups

set -e

# Get the absolute path to the backup script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup-vault.sh"
LOG_FILE="/var/log/vault-backup.log"

echo "=== Vault Backup Cron Setup ==="
echo ""
echo "This will add a cron job to backup Vault hourly."
echo "Backup script: $BACKUP_SCRIPT"
echo "Log file: $LOG_FILE"
echo ""

read -p "Continue? (y/N): " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    exit 0
fi

# Add to crontab
(crontab -l 2>/dev/null || echo ""; echo "# Vault hourly backup"; echo "0 * * * * $BACKUP_SCRIPT >> $LOG_FILE 2>&1") | crontab -

echo "✓ Cron job added"
echo ""
echo "To view: crontab -l"
echo "To remove: crontab -l | grep -v '$BACKUP_SCRIPT' | crontab -"
echo "To view logs: tail -f $LOG_FILE"