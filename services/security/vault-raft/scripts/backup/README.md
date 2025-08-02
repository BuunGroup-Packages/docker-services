# Vault Backup Scripts

Simple backup scripts for Vault.

## Usage

```bash
# Create a backup
./backup-vault.sh

# List backups
./list-backups.sh

# Restore from backup
./restore-vault.sh [TIMESTAMP]

# Setup hourly cron job
./setup-cron.sh
```

## What Gets Backed Up

- Vault Raft snapshot (all data)
- Configuration files
- TLS certificates (if present)
- Initialization keys

## Google Drive Integration

See [../google/gdrive-setup.sh](../google/gdrive-setup.sh) to setup Google Drive uploads.