#!/bin/bash
# Google Drive Setup Script for Vault Backups
# Configures OAuth2 authentication for personal Google Drive

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

echo -e "${BLUE}=== Google Drive Backup Setup (OAuth2) ===${NC}"
echo ""
echo "This wizard will help you configure Google Drive backup using OAuth2."
echo ""

# Check if already configured
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}Google Drive is already configured.${NC}"
    read -p "Do you want to reconfigure? (y/N): " reconfigure
    if [ "$reconfigure" != "y" ] && [ "$reconfigure" != "Y" ]; then
        exit 0
    fi
fi

echo -e "${BLUE}Prerequisites:${NC}"
echo ""
echo "1. Create OAuth2 credentials in Google Cloud Console:"
echo "   - Go to https://console.cloud.google.com"
echo "   - Select your project (or create a new one)"
echo "   - Go to 'APIs & Services' > 'Credentials'"
echo "   - Click 'Create Credentials' > 'OAuth 2.0 Client IDs'"
echo "   - Choose 'Desktop application'"
echo "   - Give it a name (e.g., 'vault-backup-client')"
echo "   - Click 'Create'"
echo "   - Download the JSON file"
echo ""
echo "2. Enable Google Drive API:"
echo "   - Go to 'APIs & Services' > 'Library'"
echo "   - Search for 'Google Drive API'"
echo "   - Click on it and press 'Enable'"
echo ""
read -p "Press Enter when you have completed these steps..."

# OAuth2 Credentials file
echo ""
echo -e "${BLUE}Step 1: OAuth2 Credentials File${NC}"
echo ""
echo "Paste the path to your OAuth2 credentials JSON file:"
read -p "Path: " OAUTH_JSON_PATH

# Validate file exists
if [ ! -f "$OAUTH_JSON_PATH" ]; then
    echo -e "${RED}Error: File not found: $OAUTH_JSON_PATH${NC}"
    exit 1
fi

# Validate it's a valid OAuth2 credentials file
if ! grep -q '"client_id"' "$OAUTH_JSON_PATH" || ! grep -q '"client_secret"' "$OAUTH_JSON_PATH"; then
    echo -e "${RED}Error: This doesn't appear to be a valid OAuth2 credentials file${NC}"
    exit 1
fi

# Copy credentials file to project
cp "$OAUTH_JSON_PATH" "$OAUTH_CREDENTIALS_FILE"
chmod 600 "$OAUTH_CREDENTIALS_FILE"
echo -e "${GREEN}✓ OAuth2 credentials saved${NC}"

# Extract client details
CLIENT_ID=$(grep -o '"client_id":"[^"]*' "$OAUTH_CREDENTIALS_FILE" | cut -d'"' -f4)
CLIENT_SECRET=$(grep -o '"client_secret":"[^"]*' "$OAUTH_CREDENTIALS_FILE" | cut -d'"' -f4)

echo "Client ID: ${CLIENT_ID}"

# Google Drive Folder
echo ""
echo -e "${BLUE}Step 2: Google Drive Folder${NC}"
echo ""
echo "Enter the Google Drive folder ID where backups will be stored."
echo "The folder ID is in the URL: drive.google.com/drive/folders/{FOLDER_ID}"
echo ""

while true; do
    read -p "Enter Google Drive Folder ID: " FOLDER_ID
    if [ -n "$FOLDER_ID" ]; then
        break
    fi
    echo -e "${RED}Folder ID cannot be empty${NC}"
done

# OAuth2 Authorization
echo ""
echo -e "${BLUE}Step 3: OAuth2 Authorization${NC}"
echo ""
echo "You need to authorize this application to access your Google Drive."
echo ""

# Generate authorization URL
AUTH_URL="https://accounts.google.com/o/oauth2/auth?client_id=${CLIENT_ID}&redirect_uri=urn:ietf:wg:oauth:2.0:oob&scope=https://www.googleapis.com/auth/drive.file&response_type=code&access_type=offline&prompt=consent"

echo "1. Open this URL in your browser:"
echo ""
echo -e "${YELLOW}${AUTH_URL}${NC}"
echo ""
echo "2. Sign in to your Google account"
echo "3. Grant permission to access Google Drive"
echo "4. Copy the authorization code"
echo ""

read -p "Enter the authorization code: " AUTH_CODE

if [ -z "$AUTH_CODE" ]; then
    echo -e "${RED}Authorization code cannot be empty${NC}"
    exit 1
fi

# Exchange authorization code for tokens
echo ""
echo -e "${BLUE}Getting access tokens...${NC}"

TOKEN_RESPONSE=$(curl -s -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" \
    -d "code=${AUTH_CODE}" \
    -d "grant_type=authorization_code" \
    -d "redirect_uri=urn:ietf:wg:oauth:2.0:oob" \
    "https://oauth2.googleapis.com/token")

# Check if token exchange was successful
if echo "$TOKEN_RESPONSE" | grep -q '"access_token"'; then
    echo "$TOKEN_RESPONSE" > "$OAUTH_TOKENS_FILE"
    chmod 600 "$OAUTH_TOKENS_FILE"
    echo -e "${GREEN}✓ OAuth2 tokens obtained successfully${NC}"
else
    echo -e "${RED}Error getting tokens:${NC}"
    echo "$TOKEN_RESPONSE"
    exit 1
fi

# Enable/Disable Google Drive
echo ""
echo -e "${BLUE}Step 4: Enable Google Drive Backup${NC}"
echo ""
read -p "Enable Google Drive backup? (Y/n): " ENABLE_GDRIVE
ENABLE_GDRIVE=${ENABLE_GDRIVE:-Y}

if [ "$ENABLE_GDRIVE" = "Y" ] || [ "$ENABLE_GDRIVE" = "y" ]; then
    GDRIVE_ENABLED="true"
else
    GDRIVE_ENABLED="false"
fi

# Save configuration
echo ""
echo -e "${BLUE}Saving configuration...${NC}"

cat > "$CONFIG_FILE" <<EOF
# Google Drive Configuration for Vault Backups (OAuth2)
# Generated on $(date)

# OAuth2 Client ID
GDRIVE_CLIENT_ID="$CLIENT_ID"

# Google Drive Folder ID
GDRIVE_FOLDER_ID="$FOLDER_ID"

# Enable/Disable Google Drive Backup
GDRIVE_ENABLED="$GDRIVE_ENABLED"

# Backup Types
GDRIVE_HOURLY_ENABLED="true"
GDRIVE_DAILY_ENABLED="true"

# Retention (hours for hourly, days for daily)
GDRIVE_HOURLY_RETENTION=24
GDRIVE_DAILY_RETENTION=30

# Authentication Type
GDRIVE_AUTH_TYPE="oauth2"
EOF

# Secure the config files
chmod 600 "$CONFIG_FILE"

echo -e "${GREEN}✓ Configuration saved${NC}"

# Test connection
if [ "$GDRIVE_ENABLED" = "true" ]; then
    echo ""
    echo -e "${BLUE}Testing Google Drive connection...${NC}"
    
    # Create test file
    TEST_DIR="/tmp/vault-backup-test-$(date +%s)"
    mkdir -p "$TEST_DIR"
    echo "Vault Backup Test - $(date)" > "$TEST_DIR/test.txt"
    
    # Try to upload using the OAuth2 script
    if "$SCRIPT_DIR/gdrive-upload.sh" "$TEST_DIR" "test" 2>&1 | grep -q "successfully"; then
        echo -e "${GREEN}✓ Test upload successful${NC}"
        echo ""
        echo "OAuth2 authentication is working correctly!"
    else
        echo -e "${YELLOW}! Test upload failed${NC}"
        echo ""
        echo "Please check:"
        echo "1. The folder ID is correct"
        echo "2. You have access to the folder"
        echo "3. Google Drive API is enabled"
    fi
    
    # Clean up
    rm -rf "$TEST_DIR"
fi

# Clean up original credentials file for security
if [ "$OAUTH_JSON_PATH" != "$OAUTH_CREDENTIALS_FILE" ] && [ -f "$OAUTH_JSON_PATH" ]; then
    echo ""
    echo -e "${BLUE}Security cleanup...${NC}"
    read -p "Delete the original OAuth2 credentials file for security? (Y/n): " delete_original
    delete_original=${delete_original:-Y}
    
    if [ "$delete_original" = "Y" ] || [ "$delete_original" = "y" ]; then
        rm -f "$OAUTH_JSON_PATH"
        echo -e "${GREEN}✓ Original credentials file deleted${NC}"
        echo "The credentials are now securely stored at: $OAUTH_CREDENTIALS_FILE"
    else
        echo -e "${YELLOW}! Original file kept at: $OAUTH_JSON_PATH${NC}"
        echo "Remember to delete it manually for security."
    fi
fi

# Update .gitignore
if [ -f "${PROJECT_ROOT}/.gitignore" ]; then
    if ! grep -q "^.gdrive-oauth" "${PROJECT_ROOT}/.gitignore"; then
        echo "" >> "${PROJECT_ROOT}/.gitignore"
        echo "# Google Drive OAuth2 credentials and tokens" >> "${PROJECT_ROOT}/.gitignore"
        echo ".gdrive-config" >> "${PROJECT_ROOT}/.gitignore"
        echo ".gdrive-oauth-credentials.json" >> "${PROJECT_ROOT}/.gitignore"
        echo ".gdrive-oauth-tokens.json" >> "${PROJECT_ROOT}/.gitignore"
    fi
fi

# Show summary
echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "Configuration saved to:"
echo "  - Config: $CONFIG_FILE"
echo "  - OAuth2 Credentials: $OAUTH_CREDENTIALS_FILE"
echo "  - OAuth2 Tokens: $OAUTH_TOKENS_FILE"
echo ""

if [ "$GDRIVE_ENABLED" = "true" ]; then
    echo "Google Drive backup is ENABLED"
    echo ""
    echo "Client ID: $CLIENT_ID"
    echo "Folder ID: $FOLDER_ID"
    echo ""
    echo "To set up automatic hourly backups, add to crontab:"
    echo "  0 * * * * ${PROJECT_ROOT}/scripts/backup/backup-cron.sh hourly"
    echo ""
    echo "To manually upload a backup:"
    echo "  ./scripts/google/gdrive-upload.sh /path/to/backup/directory"
else
    echo "Google Drive backup is DISABLED"
    echo ""
    echo "To enable later, run:"
    echo "  ./scripts/google/gdrive-setup.sh"
fi

echo ""
echo -e "${YELLOW}Important Security Notes:${NC}"
echo "1. Keep the OAuth2 credentials and tokens secure"
echo "2. Never commit them to version control"
echo "3. Tokens will be automatically refreshed when needed"
echo "4. You can revoke access anytime in your Google Account settings"