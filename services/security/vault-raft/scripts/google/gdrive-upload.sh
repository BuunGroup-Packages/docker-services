#!/bin/bash
# Google Drive Upload Script for Vault Backups
# Uses OAuth2 for authentication

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
CONFIG_FILE="${PROJECT_ROOT}/.gdrive-config"
OAUTH_CREDENTIALS_FILE="${PROJECT_ROOT}/.gdrive-oauth-credentials.json"
OAUTH_TOKENS_FILE="${PROJECT_ROOT}/.gdrive-oauth-tokens.json"

# Function to load configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        echo -e "${RED}Error: Google Drive configuration not found${NC}"
        echo "Run ./scripts/google/gdrive-setup.sh to configure Google Drive"
        exit 1
    fi
}

# Function to refresh OAuth2 access token
refresh_access_token() {
    if [ ! -f "$OAUTH_CREDENTIALS_FILE" ] || [ ! -f "$OAUTH_TOKENS_FILE" ]; then
        echo "Error: OAuth2 credentials or tokens not found" >&2
        echo "Run ./scripts/google/gdrive-setup.sh to configure OAuth2" >&2
        return 1
    fi
    
    # Get client credentials - handle both formats
    local client_id=""
    local client_secret=""
    
    # Try installed app format first
    if grep -q '"installed"' "$OAUTH_CREDENTIALS_FILE"; then
        client_id=$(grep -A 10 '"installed"' "$OAUTH_CREDENTIALS_FILE" | grep -o '"client_id":"[^"]*' | cut -d'"' -f4)
        client_secret=$(grep -A 10 '"installed"' "$OAUTH_CREDENTIALS_FILE" | grep -o '"client_secret":"[^"]*' | cut -d'"' -f4)
    else
        # Try direct format
        client_id=$(grep -o '"client_id":"[^"]*' "$OAUTH_CREDENTIALS_FILE" | cut -d'"' -f4)
        client_secret=$(grep -o '"client_secret":"[^"]*' "$OAUTH_CREDENTIALS_FILE" | cut -d'"' -f4)
    fi
    
    if [ -z "$client_id" ] || [ -z "$client_secret" ]; then
        echo "Error: Could not extract client_id or client_secret" >&2
        return 1
    fi
    
    # Get refresh token
    local refresh_token=$(grep -o '"refresh_token": *"[^"]*' "$OAUTH_TOKENS_FILE" | sed 's/.*": *"//' | sed 's/".*//')
    
    if [ -z "$refresh_token" ]; then
        echo "Error: No refresh token found. Re-run setup." >&2
        return 1
    fi
    
    # Refresh the access token
    local token_response=$(curl -s -X POST \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "client_id=${client_id}" \
        -d "client_secret=${client_secret}" \
        -d "refresh_token=${refresh_token}" \
        -d "grant_type=refresh_token" \
        "https://oauth2.googleapis.com/token")
    
    if echo "$token_response" | grep -q '"access_token"'; then
        # Update tokens file with new access token
        local new_access_token=$(echo "$token_response" | grep -o '"access_token": *"[^"]*' | sed 's/.*": *"//' | sed 's/".*//')
        
        # Create updated tokens file (preserve refresh token)
        local current_tokens=$(cat "$OAUTH_TOKENS_FILE")
        echo "$current_tokens" | sed "s/\"access_token\":\"[^\"]*\"/\"access_token\":\"$new_access_token\"/" > "$OAUTH_TOKENS_FILE"
        
        echo "$new_access_token"
        return 0
    else
        echo "Error refreshing token: $token_response" >&2
        return 1
    fi
}

# Function to get access token
get_access_token() {
    if [ ! -f "$OAUTH_TOKENS_FILE" ]; then
        echo -e "${RED}Error: OAuth2 tokens not found${NC}"
        echo "Run ./scripts/google/gdrive-setup.sh to configure OAuth2"
        exit 1
    fi
    
    # Try to get current access token
    local access_token=$(grep -o '"access_token": *"[^"]*' "$OAUTH_TOKENS_FILE" | sed 's/.*": *"//' | sed 's/".*//')
    
    if [ -n "$access_token" ]; then
        # Test if token is still valid by making a simple API call
        local test_response=$(curl -s -o /dev/null -w "%{http_code}" \
            -H "Authorization: Bearer $access_token" \
            "https://www.googleapis.com/drive/v3/about?fields=user")
        
        if [ "$test_response" = "200" ]; then
            echo "$access_token"
            return 0
        fi
    fi
    
    # Token is invalid or expired, refresh it
    echo -e "  Refreshing access token..." >&2
    refresh_access_token
}

# Function to upload file to Google Drive
upload_file() {
    local file_path="$1"
    local file_name="$2"
    local folder_id="$3"
    
    if [ ! -f "$file_path" ]; then
        echo -e "${RED}Error: File not found: $file_path${NC}"
        return 1
    fi
    
    echo -e "  Getting access token..."
    local access_token=$(get_access_token)
    
    echo -e "  Uploading: $file_name ($(du -h "$file_path" | cut -f1))"
    
    # Create metadata
    local metadata="{\"name\": \"$file_name\", \"parents\": [\"$folder_id\"]}"
    
    # Upload file using multipart upload
    local response=$(curl -s -X POST \
        -H "Authorization: Bearer $access_token" \
        -F "metadata=$metadata;type=application/json;charset=UTF-8" \
        -F "file=@$file_path" \
        "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")
    
    # Check if we got any response
    if [ -z "$response" ]; then
        echo -e "  ${RED}✗ Empty response from Google Drive API${NC}"
        echo -e "  This might be a network issue or API problem"
        return 1
    fi
    
    # Check for error in response
    if echo "$response" | grep -q '"error"'; then
        echo -e "  ${RED}✗ Upload failed with error${NC}"
        echo "  Response: $response"
        return 1
    fi
    
    local file_id=$(echo "$response" | grep -o '"id": *"[^"]*' | sed 's/.*": *"//' | sed 's/".*//')
    
    if [ -n "$file_id" ]; then
        echo -e "  ${GREEN}✓ Uploaded successfully (ID: $file_id)${NC}"
        return 0
    else
        echo -e "  ${RED}✗ Upload failed - no file ID in response${NC}"
        echo "  Full response: $response"
        return 1
    fi
}

# Function to list files in folder
list_folder_files() {
    local folder_id="$1"
    local access_token=$(get_access_token)
    
    local response=$(curl -s -X GET \
        -H "Authorization: Bearer $access_token" \
        "https://www.googleapis.com/drive/v3/files?q='$folder_id'+in+parents&fields=files(id,name,createdTime)")
    
    echo "$response"
}

# Function to delete file
delete_file() {
    local file_id="$1"
    local access_token=$(get_access_token)
    
    curl -s -X DELETE \
        -H "Authorization: Bearer $access_token" \
        "https://www.googleapis.com/drive/v3/files/$file_id"
}

# Function to manage hourly rotation
manage_hourly_rotation() {
    local folder_id="$1"
    local prefix="vault-backup-hourly-"
    
    echo -e "${BLUE}Managing hourly backup rotation...${NC}"
    
    # Get list of hourly backups
    local files=$(list_folder_files "$folder_id")
    
    # Parse hourly backup files (format: vault-backup-hourly-HH-YYYYMMDD)
    local hourly_files=$(echo "$files" | grep -o '"name":"vault-backup-hourly-[0-9]\{2\}-[0-9]\{8\}[^"]*"' || echo "")
    
    if [ -z "$hourly_files" ]; then
        echo "  No existing hourly backups found"
        return
    fi
    
    # Count hourly backups
    local count=$(echo "$hourly_files" | wc -l)
    echo "  Found $count hourly backups"
    
    # If we have 24 or more hourly backups, delete the oldest
    if [ "$count" -ge 24 ]; then
        echo "  Removing old hourly backups to maintain 24-hour window..."
        
        # Get file details with IDs
        local files_with_ids=$(echo "$files" | grep -B1 -A1 'vault-backup-hourly-')
        
        # Sort by name (which includes timestamp) and get the oldest
        local oldest_file=$(echo "$hourly_files" | sort | head -1)
        local oldest_name=$(echo "$oldest_file" | cut -d'"' -f4)
        
        # Find the ID of the oldest file
        local oldest_id=$(echo "$files" | grep -B2 "$oldest_name" | grep -o '"id":"[^"]*' | cut -d'"' -f4 | head -1)
        
        if [ -n "$oldest_id" ]; then
            echo "  Deleting: $oldest_name"
            delete_file "$oldest_id"
            echo -e "  ${GREEN}✓ Deleted old backup${NC}"
        fi
    fi
}

# Main upload function
main() {
    local backup_path="$1"
    local upload_type="${2:-manual}"  # manual, hourly, or daily
    
    # Load configuration
    load_config
    
    # Check if Google Drive is enabled
    if [ "${GDRIVE_ENABLED:-false}" != "true" ]; then
        echo -e "${YELLOW}Google Drive backup is disabled${NC}"
        exit 0
    fi
    
    if [ ! -d "$backup_path" ]; then
        echo -e "${RED}Error: Backup directory not found: $backup_path${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}=== Google Drive Backup Upload ===${NC}"
    echo -e "Backup: $(basename "$backup_path")"
    echo -e "Type: $upload_type"
    echo -e "Using OAuth2 authentication"
    echo ""
    
    # Prepare upload name based on type
    local timestamp=$(basename "$backup_path")
    local upload_name=""
    
    case "$upload_type" in
        hourly)
            # Format: vault-backup-hourly-HH-YYYYMMDD
            local hour=$(date +%H)
            local date=$(date +%Y%m%d)
            upload_name="vault-backup-hourly-${hour}-${date}"
            
            # Manage rotation before upload
            manage_hourly_rotation "$GDRIVE_FOLDER_ID"
            ;;
        daily)
            # Format: vault-backup-daily-YYYYMMDD
            upload_name="vault-backup-daily-$(date +%Y%m%d)"
            ;;
        *)
            # Format: vault-backup-manual-TIMESTAMP
            upload_name="vault-backup-manual-$timestamp"
            ;;
    esac
    
    # Create tar archive of the backup directory
    echo -e "${BLUE}Creating archive for upload...${NC}"
    local temp_archive="${PROJECT_ROOT}/${upload_name}.tar.gz"
    
    # Use sudo if needed to read backup files
    if [ ! -r "$backup_path/manifest.json" ] && command -v sudo >/dev/null 2>&1; then
        echo -e "  Using sudo to access backup files..."
        sudo tar czf "$temp_archive" -C "$(dirname "$backup_path")" "$(basename "$backup_path")"
        # Make the archive readable by current user
        sudo chown "$(id -u):$(id -g)" "$temp_archive"
    else
        tar czf "$temp_archive" -C "$(dirname "$backup_path")" "$(basename "$backup_path")"
    fi
    
    # Upload to Google Drive
    echo -e "\n${BLUE}Uploading to Google Drive...${NC}"
    if upload_file "$temp_archive" "${upload_name}.tar.gz" "$GDRIVE_FOLDER_ID"; then
        echo -e "\n${GREEN}✓ Backup uploaded successfully to Google Drive${NC}"
        
        # Clean up temp file
        rm -f "$temp_archive"
        
        # Log success
        mkdir -p "${PROJECT_ROOT}/logs"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: Uploaded $upload_name to Google Drive" >> "${PROJECT_ROOT}/logs/gdrive-upload.log"
    else
        echo -e "\n${RED}✗ Failed to upload backup to Google Drive${NC}"
        rm -f "$temp_archive"
        
        # Log failure
        mkdir -p "${PROJECT_ROOT}/logs"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] FAILED: Upload of $upload_name failed" >> "${PROJECT_ROOT}/logs/gdrive-upload.log"
        exit 1
    fi
}

# Run main function
main "$@"