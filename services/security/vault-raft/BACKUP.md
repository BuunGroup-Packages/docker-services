# Vault Backup and Restore Guide

This guide covers backing up and restoring your HashiCorp Vault instance with Raft storage.

## Quick Start

### Create a Backup
```bash
./scripts/backup/backup-vault.sh
```

### List Backups
```bash
./scripts/backup/list-backups.sh
```

### Restore a Backup
```bash
./scripts/backup/restore-vault.sh [TIMESTAMP]
# Example: ./scripts/backup/restore-vault.sh 20240801-120000
```

## What Gets Backed Up

Each backup includes:

1. **Raft Snapshot** (`vault-raft.snap`)
   - All Vault data including:
     - Secrets and secret engines
     - Authentication methods and users
     - Policies
     - Audit devices
     - System configuration

2. **Initialization Keys** (`vault-keys.tar.gz`)
   - Unseal keys
   - Root token
   - Initialization status

3. **Configuration** (`vault-config.tar.gz`)
   - Vault configuration files
   - Policies definitions
   - Docker compose files
   - Scripts
   - Environment settings

4. **TLS Certificates** (`vault-certs.tar.gz`) - *Only if TLS is enabled*
   - CA certificate
   - Server certificates
   - Private keys

## Backup Scripts

### backup-vault.sh
Creates a complete backup of your Vault instance.

**Features:**
- Auto-detects TLS configuration
- Creates timestamped backups
- Includes manifest with metadata
- Works with sealed/unsealed Vault

**Usage:**
```bash
# Basic backup (uses root token from container if available)
./scripts/backup/backup-vault.sh

# Backup with specific root token
export VAULT_TOKEN="hvs.xxxxxxxxxxxxx"
./scripts/backup/backup-vault.sh
```

### restore-vault.sh
Restores Vault from a backup to the same or different machine.

**Features:**
- Interactive restore process
- Validates backup before restoring
- Handles TLS and non-TLS configurations
- Attempts automatic unsealing

**Usage:**
```bash
# Interactive restore (lists available backups)
./scripts/backup/restore-vault.sh

# Direct restore
./scripts/backup/restore-vault.sh 20240801-120000
```

### list-backups.sh
Shows all available backups with details.

**Output includes:**
- Timestamp and date
- Backup size
- TLS status
- Validation status

### verify-backup.sh
Verifies backup integrity.

**Usage:**
```bash
./scripts/backup/verify-backup.sh 20240801-120000
```

**Checks:**
- Manifest validity
- File presence and integrity
- Archive validity
- Snapshot format

### backup-cron.sh
Wrapper for automated backups via cron with Google Drive support.

**Features:**
- Hourly and daily backup modes
- Google Drive integration
- Logging to files
- Retention management
- Lock file to prevent concurrent runs
- Automatic verification

**Usage:**
```bash
# Daily backup (default)
./scripts/backup/backup-cron.sh

# Hourly backup
./scripts/backup/backup-cron.sh hourly
```

## Google Drive Integration

### Setup Google Drive

Configure Google Drive backup uploads:
```bash
./scripts/google/gdrive-setup.sh
```

**Requirements:**
1. Google Cloud Console project with Google Drive API enabled
2. Service Account with JSON key file
3. Google Drive folder shared with the service account
4. Python 3 with pyjwt and requests packages (optional, for better compatibility)
   OR Google Cloud SDK installed (optional)

**Features:**
- Automatic upload after local backup
- Hourly backups: 24-hour rotation on Google Drive
- Daily backups: Configurable retention (default 30 days)
- Enable/disable per backup type

### Authentication Methods

The Google Drive integration supports multiple authentication methods:

1. **Python Helper** (Recommended)
   ```bash
   pip install pyjwt requests
   ```
   Uses the included `gdrive-auth.py` script for JWT generation

2. **Google Cloud SDK**
   ```bash
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   ```
   Uses `gcloud auth` for token generation

3. **Manual Setup**
   If neither is available, the script will provide instructions

### Google Drive Scripts

**gdrive-upload.sh**
```bash
# Manual upload
./scripts/google/gdrive-upload.sh /path/to/backup/directory

# Upload with type (for rotation management)
./scripts/google/gdrive-upload.sh /path/to/backup hourly
./scripts/google/gdrive-upload.sh /path/to/backup daily
```

**gdrive-setup.sh**
- Interactive setup wizard
- Configures Service Account authentication
- Tests connection
- Saves credentials securely
- Provides step-by-step Google Cloud setup instructions

## Automated Backups

### Quick Setup

Use the automated setup script:
```bash
./scripts/backup/setup-cron.sh
```

Options:
1. Hourly backups only (24-hour rotation)
2. Daily backups only (30-day retention)
3. Both hourly and daily backups
4. Remove all backup cron jobs

### Manual Cron Setup

Add to crontab for different schedules:
```bash
# Hourly backups
0 * * * * /path/to/vault-raft/scripts/backup/backup-cron.sh hourly

# Daily backups at 2 AM
0 2 * * * /path/to/vault-raft/scripts/backup/backup-cron.sh daily

# Both schedules
0 * * * * /path/to/vault-raft/scripts/backup/backup-cron.sh hourly
0 2 * * * /path/to/vault-raft/scripts/backup/backup-cron.sh daily
```

### Using systemd Timer

Create `/etc/systemd/system/vault-backup.service`:
```ini
[Unit]
Description=Vault Backup
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/path/to/vault-raft/scripts/backup/backup-cron.sh
User=your-user
```

Create `/etc/systemd/system/vault-backup.timer`:
```ini
[Unit]
Description=Daily Vault Backup
Requires=vault-backup.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

Enable and start:
```bash
sudo systemctl enable vault-backup.timer
sudo systemctl start vault-backup.timer
```

## Backup Retention

Configure retention in `backup-cron.sh` or via environment:

```bash
# Keep backups for 30 days (default)
export VAULT_BACKUP_RETENTION_DAYS=30

# Keep only 10 most recent backups
export VAULT_BACKUP_RETENTION_COUNT=10
```

## Migration Scenarios

### Same Machine Restore

Restore after configuration changes or issues:
```bash
# 1. List backups
./scripts/backup/list-backups.sh

# 2. Restore specific backup
./scripts/backup/restore-vault.sh 20240801-120000
```

### Cross-Machine Migration

Move Vault to a new VM:

**On Source Machine:**
```bash
# 1. Create backup
./scripts/backup/backup-vault.sh

# 2. Copy backup directory to new machine
rsync -av backups/20240801-120000/ user@new-vm:/path/to/vault-raft/backups/20240801-120000/
```

**On Target Machine:**
```bash
# 1. Clone or copy vault-raft directory structure
git clone <your-repo>
cd vault-raft

# 2. Restore backup
./scripts/backup/restore-vault.sh 20240801-120000
```

### TLS to Non-TLS Migration

The restore script handles this automatically:
```bash
# Backup was created with TLS, restore without TLS
./scripts/backup/restore-vault.sh 20240801-120000

# The script will warn about TLS mismatch but proceed
```

## Disaster Recovery

### Complete System Failure

1. **Prepare New System**
   ```bash
   # Install Docker
   curl -fsSL https://get.docker.com | bash
   
   # Clone repository or copy files
   git clone <your-repo>
   cd vault-raft
   ```

2. **Restore from Backup**
   ```bash
   # Copy backup files
   mkdir -p backups
   cp -r /backup-location/* backups/
   
   # Restore
   ./scripts/backup/restore-vault.sh
   ```

### Partial Recovery

If Vault is running but data is corrupted:

1. **Export Current State** (if possible)
   ```bash
   ./scripts/backup/backup-vault.sh
   ```

2. **Clean and Restore**
   ```bash
   ./scripts/cleanup/cleanup.sh
   ./scripts/backup/restore-vault.sh <good-backup-timestamp>
   ```

## Security Considerations

### Backup Storage

1. **Encryption at Rest**
   ```bash
   # Encrypt backup
   tar czf - backups/20240801-120000 | gpg -c > vault-backup-20240801.tar.gz.gpg
   
   # Decrypt backup
   gpg -d vault-backup-20240801.tar.gz.gpg | tar xzf -
   ```

2. **Secure Transfer**
   ```bash
   # Use SSH for remote backup
   rsync -av -e ssh backups/ user@backup-server:/secure/location/
   ```

3. **Access Control**
   - Limit backup directory permissions: `chmod 700 backups/`
   - Store in secure location with restricted access
   - Consider using cloud object storage with encryption

### Sensitive Data

Backups contain:
- All secrets stored in Vault
- Unseal keys
- Root token
- TLS private keys (if enabled)

**Never:**
- Store backups in public repositories
- Transfer over unencrypted connections
- Leave backups on shared systems

## Troubleshooting

### Backup Fails

1. **"Vault container is not running"**
   - Start Vault: `docker compose up -d`

2. **"Permission denied"**
   - Check file permissions
   - Run with appropriate user

3. **"No root token available"**
   ```bash
   # Provide token manually
   export VAULT_TOKEN="your-root-token"
   ./scripts/backup/backup-vault.sh
   ```

### Restore Fails

1. **"Invalid backup - manifest.json not found"**
   - Verify backup integrity: `./scripts/backup/verify-backup.sh TIMESTAMP`

2. **"Failed to restore snapshot"**
   - Ensure Vault is unsealed
   - Check root token is correct
   - Verify Vault version compatibility

3. **"Unable to unseal"**
   - Check unseal keys in backup
   - Manually unseal if automatic fails

## Best Practices

1. **Regular Backups**
   - Daily automated backups minimum
   - Before any major changes
   - After adding important secrets

2. **Test Restores**
   - Regular restore drills
   - Test on separate environment
   - Verify data integrity

3. **Multiple Backup Locations**
   - Local backups for quick recovery
   - Remote backups for disaster recovery
   - Cloud storage for redundancy

4. **Documentation**
   - Document backup procedures
   - Keep restoration guide accessible
   - Maintain backup inventory

5. **Monitoring**
   - Check backup job success
   - Monitor backup size growth
   - Alert on backup failures

## Backup Manifest Format

Each backup includes a `manifest.json`:

```json
{
  "timestamp": "20240801-120000",
  "date": "2024-08-01 12:00:00 UTC",
  "tls_enabled": true,
  "vault_sealed": false,
  "vault_version": "Vault v1.15.0",
  "backup_version": "1.0",
  "backup_size": "125M",
  "files": {
    "raft_snapshot": "vault-raft.snap",
    "keys": "vault-keys.tar.gz",
    "config": "vault-config.tar.gz",
    "certs": "vault-certs.tar.gz"
  }
}
```

This helps identify and validate backups without extracting them.