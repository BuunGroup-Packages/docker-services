#!/bin/bash

# Dokploy Deployment Script
# Simple deployment for Dokploy using Docker Compose

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Dokploy Deployment Script ===${NC}"

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${YELLOW}No .env file found. Creating from example...${NC}"
    cp .env.example .env
    
    # Ask for custom port
    read -p "Enter Dokploy port [3000]: " DOKPLOY_PORT
    DOKPLOY_PORT=${DOKPLOY_PORT:-3000}
    sed -i.bak "s/DOKPLOY_PORT=.*/DOKPLOY_PORT=$DOKPLOY_PORT/" .env
    
    # Clean up backup
    rm -f .env.bak
fi

# Source the .env file
source .env

# Check if required directories exist
echo -e "${YELLOW}Setting up directories...${NC}"
mkdir -p traefik/dynamic
sudo mkdir -p /etc/dokploy
sudo chmod 777 /etc/dokploy

# Check for port conflicts
if lsof -Pi :80 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${RED}Error: Port 80 is already in use${NC}"
    echo "Please stop the service using port 80 or modify docker-compose.yml"
    exit 1
fi

if lsof -Pi :443 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${RED}Error: Port 443 is already in use${NC}"
    echo "Please stop the service using port 443 or modify docker-compose.yml"
    exit 1
fi

if lsof -Pi :${DOKPLOY_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${RED}Error: Port ${DOKPLOY_PORT} is already in use${NC}"
    echo "Please choose a different port in .env file"
    exit 1
fi

# Pull latest images
echo -e "${YELLOW}Pulling latest images...${NC}"
docker-compose pull

# Start services
echo -e "${YELLOW}Starting Dokploy services...${NC}"
docker-compose up -d

# Wait for services to be ready
echo -e "${YELLOW}Waiting for services to be ready...${NC}"
echo -n "Starting"
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:${DOKPLOY_PORT} | grep -q "308"; then
        echo -e "\n${GREEN}Dokploy is ready!${NC}"
        break
    fi
    echo -n "."
    sleep 2
done

# Display service status
echo -e "\n${GREEN}=== Service Status ===${NC}"
docker-compose ps

# Display access information
echo -e "\n${GREEN}=== Access Information ===${NC}"
echo -e "Dokploy URL: ${BLUE}http://localhost:${DOKPLOY_PORT}${NC}"
echo -e "Traefik is running on ports 80 and 443"
echo ""
echo -e "${YELLOW}First time setup:${NC}"
echo "1. Go to http://localhost:${DOKPLOY_PORT}"
echo "2. You'll be redirected to /register"
echo "3. Create your admin account"
echo "4. Start deploying your applications!"
echo ""
echo -e "${GREEN}Deployment completed successfully!${NC}"