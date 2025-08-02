#!/bin/bash

# Dokploy Setup Script for Azure VM

set -e

echo "==================================="
echo "Dokploy Azure VM Setup Script"
echo "==================================="
echo ""

# Get VM public IP
PUBLIC_IP=$(curl -s ifconfig.me)
echo "Detected public IP: $PUBLIC_IP"
echo ""

# Create .env file if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating .env file..."
    
    # Generate secrets
    SECRET_KEY=$(openssl rand -hex 32)
    BETTER_AUTH_SECRET=$(openssl rand -hex 32)
    WEBHOOK_SECRET=$(openssl rand -hex 32)
    
    cat > .env << EOF
# Dokploy Environment Configuration
DOKPLOY_PORT=3000

# Security Keys
SECRET_KEY=$SECRET_KEY
BETTER_AUTH_SECRET=$BETTER_AUTH_SECRET
WEBHOOK_SECRET=$WEBHOOK_SECRET

# Admin Credentials
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=changeme

# Database Configuration
POSTGRES_DB=dokploy
POSTGRES_USER=dokploy
POSTGRES_PASSWORD=$(openssl rand -hex 16)

# Base URL
BASE_URL=http://$PUBLIC_IP:3000

# GitHub Integration (Optional)
GITHUB_APP_ID=
GITHUB_APP_PRIVATE_KEY=
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=

# Email Configuration (Optional)
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM=noreply@example.com
EOF
    
    echo "✓ .env file created"
    echo ""
    echo "IMPORTANT: Please update the admin credentials in .env file!"
    echo ""
fi

# Fix Redis memory overcommit
echo "Fixing Redis memory configuration..."
if [ -f ./fix-redis-memory.sh ]; then
    ./fix-redis-memory.sh
else
    sudo sysctl vm.overcommit_memory=1
    echo "vm.overcommit_memory = 1" | sudo tee -a /etc/sysctl.conf > /dev/null
fi
echo "✓ Redis memory configuration fixed"
echo ""

# Stop existing containers
echo "Stopping existing containers..."
docker compose down || true
echo ""

# Start Dokploy
echo "Starting Dokploy..."
docker compose up -d
echo ""

# Wait for services to be healthy
echo "Waiting for services to start..."
sleep 10

# Check status
echo "Checking service status..."
docker compose ps
echo ""

# Check logs for errors
echo "Checking for errors..."
if docker compose logs dokploy 2>&1 | grep -q "ELIFECYCLE"; then
    echo "⚠️  Errors detected in Dokploy logs:"
    docker compose logs dokploy --tail=20
else
    echo "✓ Dokploy appears to be running"
fi
echo ""

# Azure NSG reminder
echo "==================================="
echo "IMPORTANT: Azure Network Security"
echo "==================================="
echo ""
echo "Make sure port 3000 is open in your Azure Network Security Group!"
echo ""
echo "Run this command in Azure Cloud Shell or CLI:"
echo ""
echo "az network nsg rule create \\"
echo "  --resource-group YOUR_RESOURCE_GROUP \\"
echo "  --nsg-name YOUR_NSG_NAME \\"
echo "  --name AllowDokploy \\"
echo "  --priority 100 \\"
echo "  --source-address-prefixes '*' \\"
echo "  --destination-port-ranges 3000 \\"
echo "  --protocol Tcp \\"
echo "  --access Allow \\"
echo "  --direction Inbound"
echo ""
echo "==================================="
echo ""
echo "Access Dokploy at: http://$PUBLIC_IP:3000"
echo ""