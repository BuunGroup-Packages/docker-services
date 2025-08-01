#!/bin/bash
# Smart cleanup script for Vault deployment
# Detects running configuration and cleans up accordingly

set -e

echo "=== Vault Cleanup Script ==="
echo ""

# Function to check if a container is running
container_exists() {
    docker ps -a --format '{{.Names}}' | grep -q "^$1$"
}


# Detect what's running
echo "Detecting current deployment..."

HA_MODE=false
TLS_MODE=false
INIT_MODE=false

# Check for HA mode
if container_exists "vault-2" || container_exists "vault-3" || container_exists "vault-haproxy"; then
    HA_MODE=true
    echo "✓ HA mode detected"
fi

# Check for TLS mode by looking for cert-generator container
if container_exists "vault-raft-cert-generator-1"; then
    TLS_MODE=true
    echo "✓ TLS mode detected"
fi

# Check for init container
if container_exists "vault-init"; then
    INIT_MODE=true
    echo "✓ Init container detected"
fi

# Check for single node
if container_exists "vault" && [ "$HA_MODE" = "false" ]; then
    echo "✓ Single node mode detected"
fi

echo ""

# Build the compose command
COMPOSE_CMD="docker compose"
if [ "$TLS_MODE" = "true" ]; then
    COMPOSE_CMD="$COMPOSE_CMD -f docker-compose.yml -f docker-compose.tls.yml"
fi

# Add appropriate profiles
if [ "$HA_MODE" = "true" ]; then
    PROFILES="--profile ha"
elif [ "$INIT_MODE" = "true" ]; then
    PROFILES="--profile init"
else
    PROFILES=""
fi

# Perform cleanup
echo "Stopping containers..."
$COMPOSE_CMD $PROFILES down 2>/dev/null || true

echo ""
echo "Removing volumes..."
# List all vault-related volumes
VOLUMES=$(docker volume ls --format '{{.Name}}' | grep '^vault-raft_' || true)

if [ -n "$VOLUMES" ]; then
    echo "Found volumes:"
    echo "$VOLUMES" | sed 's/^/  - /'
    echo "Removing volumes..."
    
    $COMPOSE_CMD $PROFILES down -v 2>/dev/null || true
    # Also remove any orphaned volumes
    for vol in $VOLUMES; do
        docker volume rm $vol 2>/dev/null || true
    done
    echo "✓ Volumes removed"
else
    echo "No volumes found"
fi

# Clean up certificates
if [ -d "./certs" ]; then
    echo ""
    echo "Removing TLS certificates..."
    # Try to remove as current user first, if that fails use docker
    rm -rf ./certs 2>/dev/null || docker run --rm -v "$PWD/certs:/certs" busybox rm -rf /certs
    echo "✓ Certificates removed"
fi

# Clean up any dangling images
echo ""
echo "Checking for dangling images..."
DANGLING=$(docker images -f "dangling=true" -q | grep -E 'vault|haproxy' || true)
if [ -n "$DANGLING" ]; then
    echo "Removing dangling images..."
    docker rmi $DANGLING 2>/dev/null || true
    echo "✓ Dangling images removed"
fi

# Clean up cert-generator image
echo ""
echo "Checking for cert-generator image..."
CERT_GEN_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E 'cert-generator|vault-raft.*cert-generator' || true)
if [ -n "$CERT_GEN_IMAGE" ]; then
    echo "Removing cert-generator image..."
    for img in $CERT_GEN_IMAGE; do
        docker rmi $img 2>/dev/null || true
    done
    echo "✓ Cert-generator image removed"
fi

# Clean up vault-init image
echo ""
echo "Checking for vault-init image..."
VAULT_INIT_IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep -E '^vault-init:latest$' || true)
if [ -n "$VAULT_INIT_IMAGE" ]; then
    echo "Removing vault-init image..."
    docker rmi $VAULT_INIT_IMAGE 2>/dev/null || true
    echo "✓ Vault-init image removed"
fi

# Remove any orphaned networks
echo ""
echo "Checking for orphaned networks..."
NETWORKS=$(docker network ls --format '{{.Name}}' | grep '^vault-raft_' || true)
if [ -n "$NETWORKS" ]; then
    for net in $NETWORKS; do
        docker network rm $net 2>/dev/null || true
    done
    echo "✓ Networks cleaned up"
fi

# Final status
echo ""
echo "=== Cleanup Complete ==="
echo ""

# Check if anything is still running
if docker ps | grep -q vault; then
    echo "⚠ Warning: Some Vault containers are still running:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep vault
else
    echo "✓ All Vault containers stopped"
fi

# Show remaining resources
REMAINING_VOLUMES=$(docker volume ls --format '{{.Name}}' | grep '^vault-raft_' || true)
if [ -n "$REMAINING_VOLUMES" ]; then
    echo ""
    echo "⚠ Remaining volumes:"
    echo "$REMAINING_VOLUMES" | sed 's/^/  - /'
fi

if [ -d "./certs" ]; then
    echo ""
    echo "⚠ TLS certificates still present in ./certs"
fi

echo ""
echo "To start fresh:"
echo "  Single node:        docker compose up -d"
echo "  HA mode:           docker compose --profile ha up -d"
echo "  HA with TLS:       docker compose -f docker-compose.yml -f docker-compose.tls.yml --profile ha up -d"
echo ""