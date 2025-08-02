#!/bin/bash

# Dokploy Cleanup Script
# Completely removes Dokploy and all associated data

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}=== Dokploy Cleanup Script ===${NC}"
echo -e "${YELLOW}WARNING: This will remove all Dokploy data!${NC}"
echo ""

# Confirm deletion
read -p "Are you sure you want to remove Dokploy and all its data? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Stop and remove containers
echo -e "${YELLOW}Stopping Dokploy services...${NC}"
docker-compose down 2>/dev/null || true

# Remove volumes
echo -e "${YELLOW}Removing Docker volumes...${NC}"
docker volume rm dokploy_postgres-data 2>/dev/null || true
docker volume rm dokploy_redis-data 2>/dev/null || true
docker volume rm dokploy_dokploy-docker-config 2>/dev/null || true

# Remove network
echo -e "${YELLOW}Removing Docker network...${NC}"
docker network rm dokploy-network 2>/dev/null || true

# Remove system directories
echo -e "${YELLOW}Removing system directories...${NC}"
sudo rm -rf /etc/dokploy 2>/dev/null || true

# Remove local directories
echo -e "${YELLOW}Removing local directories...${NC}"
rm -rf traefik/dynamic/* 2>/dev/null || true

# Optional: Remove images
read -p "Do you also want to remove Docker images? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Removing Docker images...${NC}"
    docker rmi dokploy/dokploy:latest 2>/dev/null || true
    docker rmi traefik:v3.1.2 2>/dev/null || true
    docker rmi postgres:15 2>/dev/null || true
    docker rmi redis:7 2>/dev/null || true
fi

echo -e "${GREEN}Cleanup completed!${NC}"
echo ""
echo "To reinstall Dokploy, run: ./deploy-dokploy.sh"