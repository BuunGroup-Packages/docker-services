#!/bin/bash
# Setup Cron Jobs for Vault Backups
# Configures hourly and daily backup cron jobs

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
CONFIG_FILE="${PROJECT_ROOT}/.gdrive-config"

echo -e "${BLUE}=== Vault Backup Cron Setup ===${NC}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   echo -e "${YELLOW}Warning: Running as root. Cron jobs will be installed for root user.${NC}"
   read -p "Continue? (y/N): " confirm
   if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
       exit 0
   fi
fi

# Load Google Drive config if exists
GDRIVE_ENABLED="false"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Function to check if cron job exists
cron_exists() {
    local pattern="$1"
    crontab -l 2>/dev/null | grep -q "$pattern"
}

# Function to add cron job
add_cron() {
    local schedule="$1"
    local command="$2"
    local description="$3"
    
    if cron_exists "$command"; then
        echo -e "${YELLOW}! $description already exists${NC}"
        return
    fi
    
    # Add to crontab
    (crontab -l 2>/dev/null || echo ""; echo "# $description"; echo "$schedule $command") | crontab -
    echo -e "${GREEN}✓ Added: $description${NC}"
}

# Show current configuration
echo -e "${BLUE}Current Configuration:${NC}"
echo "  Script Directory: $SCRIPT_DIR"
echo "  Google Drive Enabled: $GDRIVE_ENABLED"
echo ""

# Ask user what to set up
echo -e "${BLUE}Select backup schedule:${NC}"
echo "1. Hourly backups only (24-hour rotation)"
echo "2. Daily backups only (30-day retention)"
echo "3. Both hourly and daily backups"
echo "4. Remove all backup cron jobs"
echo ""
read -p "Enter your choice (1-4): " choice

case $choice in
    1)
        # Hourly backups
        echo ""
        echo -e "${BLUE}Setting up hourly backups...${NC}"
        
        add_cron "0 * * * *" "${PROJECT_ROOT}/scripts/backup/backup-cron.sh hourly" "Vault hourly backup"
        
        if [ "$GDRIVE_ENABLED" = "true" ]; then
            echo ""
            echo -e "${GREEN}Google Drive is enabled. Hourly backups will be uploaded automatically.${NC}"
            echo "24-hour rotation will be maintained on Google Drive."
        fi
        ;;
        
    2)
        # Daily backups
        echo ""
        echo -e "${BLUE}Setting up daily backups...${NC}"
        
        # Ask for time
        read -p "Enter hour for daily backup (0-23) [default: 2]: " hour
        hour=${hour:-2}
        
        add_cron "0 $hour * * *" "${PROJECT_ROOT}/scripts/backup/backup-cron.sh daily" "Vault daily backup"
        
        if [ "$GDRIVE_ENABLED" = "true" ]; then
            echo ""
            echo -e "${GREEN}Google Drive is enabled. Daily backups will be uploaded automatically.${NC}"
        fi
        ;;
        
    3)
        # Both
        echo ""
        echo -e "${BLUE}Setting up hourly and daily backups...${NC}"
        
        # Hourly
        add_cron "0 * * * *" "${PROJECT_ROOT}/scripts/backup/backup-cron.sh hourly" "Vault hourly backup"
        
        # Daily
        read -p "Enter hour for daily backup (0-23) [default: 2]: " hour
        hour=${hour:-2}
        add_cron "0 $hour * * *" "${PROJECT_ROOT}/scripts/backup/backup-cron.sh daily" "Vault daily backup"
        
        if [ "$GDRIVE_ENABLED" = "true" ]; then
            echo ""
            echo -e "${GREEN}Google Drive is enabled. Both backup types will be uploaded automatically.${NC}"
            echo "- Hourly: 24-hour rotation on Google Drive"
            echo "- Daily: 30-day retention on Google Drive"
        fi
        ;;
        
    4)
        # Remove
        echo ""
        echo -e "${YELLOW}Removing backup cron jobs...${NC}"
        
        # Remove all vault backup related cron jobs
        crontab -l 2>/dev/null | grep -v "backup-cron.sh" | crontab - || true
        
        echo -e "${GREEN}✓ Removed all Vault backup cron jobs${NC}"
        ;;
        
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

# Show current crontab
echo ""
echo -e "${BLUE}Current Vault backup cron jobs:${NC}"
crontab -l 2>/dev/null | grep -E "(Vault|backup-cron.sh)" || echo "  No Vault backup jobs found"

# Show log location
echo ""
echo -e "${BLUE}Backup logs will be stored in:${NC}"
echo "  ${PROJECT_ROOT}/logs/"

# Google Drive setup reminder
if [ "$GDRIVE_ENABLED" != "true" ] && [ "$choice" != "4" ]; then
    echo ""
    echo -e "${YELLOW}Google Drive backup is not configured.${NC}"
    echo "To enable Google Drive uploads, run:"
    echo "  ./scripts/google/gdrive-setup.sh"
fi

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"

# Show how to monitor
echo ""
echo "To monitor backup jobs:"
echo "  - View logs: tail -f ${PROJECT_ROOT}/logs/backup-*.log"
echo "  - List backups: ./scripts/backup/list-backups.sh"
echo "  - Check cron: crontab -l"

# Test reminder
if [ "$choice" != "4" ]; then
    echo ""
    echo -e "${YELLOW}Tip: Test your backup setup:${NC}"
    echo "  ./scripts/backup/backup-cron.sh hourly  # Test hourly backup"
    echo "  ./scripts/backup/backup-cron.sh daily   # Test daily backup"
fi