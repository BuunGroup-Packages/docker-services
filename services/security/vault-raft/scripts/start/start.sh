#!/bin/bash
# Quick start script for Vault deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Vault Quick Start ==="
echo ""

# Parse arguments
MODE="single"
TLS=false
INIT=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --ha)
            MODE="ha"
            shift
            ;;
        --tls)
            TLS=true
            shift
            ;;
        --no-init)
            INIT=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --ha        Start in HA mode (3 nodes)"
            echo "  --tls       Enable TLS"
            echo "  --no-init   Skip initialization"
            echo "  --help      Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                    # Single node, no TLS"
            echo "  $0 --ha               # HA mode, no TLS"
            echo "  $0 --ha --tls         # HA mode with TLS"
            echo "  $0 --tls              # Single node with TLS"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "Creating .env file from template..."
    cp .env.example .env
    echo -e "${GREEN}✓ Created .env file${NC}"
    echo -e "${YELLOW}⚠ Remember to update passwords in .env for production!${NC}"
fi

# Build compose command
COMPOSE_CMD="docker compose"
if [ "$TLS" = true ]; then
    COMPOSE_CMD="$COMPOSE_CMD -f docker-compose.yml -f docker-compose.tls.yml"
fi

# Add profile for HA mode
PROFILE=""
if [ "$MODE" = "ha" ]; then
    PROFILE="--profile ha"
fi

# Display configuration
echo ""
echo "Configuration:"
echo "  Mode: $MODE"
echo "  TLS: $TLS"
echo "  Auto-init: $INIT"
echo ""

# Start services
echo "Starting Vault services..."
$COMPOSE_CMD $PROFILE up -d

# Wait for services to be ready
echo ""
echo "Waiting for services to start..."
if [ "$MODE" = "ha" ]; then
    # Wait for all nodes in HA mode
    SUCCESS=false
    for i in {1..30}; do
        # Check if containers are running and vault binary is accessible
        # This works whether Vault is sealed or not
        if docker exec vault vault version >/dev/null 2>&1 && \
           docker exec vault-2 vault version >/dev/null 2>&1 && \
           docker exec vault-3 vault version >/dev/null 2>&1; then
            echo -e "${GREEN}✓ All nodes are responding${NC}"
            SUCCESS=true
            break
        fi
        echo -n "."
        sleep 2
    done
    if [ "$SUCCESS" = false ]; then
        echo -e "${YELLOW}⚠ Services may still be starting. Continuing...${NC}"
    fi
else
    # Wait for single node
    SUCCESS=false
    for i in {1..20}; do
        # Check if container is running and vault binary is accessible
        if docker exec vault vault version >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Vault is responding${NC}"
            SUCCESS=true
            break
        fi
        echo -n "."
        sleep 1
    done
    if [ "$SUCCESS" = false ]; then
        echo -e "${YELLOW}⚠ Service may still be starting. Continuing...${NC}"
    fi
fi

# Run initialization if requested
if [ "$INIT" = true ]; then
    echo ""
    echo "Running initialization..."
    if $COMPOSE_CMD --profile init run --rm vault-init; then
        echo -e "${GREEN}✓ Initialization complete${NC}"
        
        # Check if backup setup was requested
        if docker run --rm -v vault-raft_vault_keys:/keys:ro busybox test -f /keys/setup-backups-requested 2>/dev/null; then
            echo ""
            echo "Setting up automated backups as requested..."
            if [ -f "./scripts/backup/setup-cron.sh" ]; then
                ./scripts/backup/setup-cron.sh
                # Clean up the flag file
                docker run --rm -v vault-raft_vault_keys:/keys busybox rm -f /keys/setup-backups-requested 2>/dev/null || true
            else
                echo -e "${YELLOW}Warning: Backup setup script not found${NC}"
                echo "Please run: ./scripts/backup/setup-cron.sh"
            fi
        fi
    else
        echo -e "${RED}✗ Initialization failed${NC}"
        exit 1
    fi
fi

# Display access information
echo ""
echo "=== Vault is Ready! ==="
echo ""

# Get root token if available
ROOT_TOKEN=$(docker run --rm -v vault-raft_vault_keys:/vault/keys busybox cat /vault/keys/root-token.txt 2>/dev/null || echo "Not available")

if [ "$TLS" = true ]; then
    VAULT_ADDR="https://localhost:8200"
    if [ "$MODE" = "ha" ]; then
        VAULT_ADDR_HA="https://localhost:8300"
    fi
else
    VAULT_ADDR="http://localhost:8200"
    if [ "$MODE" = "ha" ]; then
        VAULT_ADDR_HA="http://localhost:8300"
    fi
fi

echo "Access URLs:"
echo "  Vault UI: $VAULT_ADDR"
if [ "$MODE" = "ha" ]; then
    echo "  Vault UI (via HAProxy): $VAULT_ADDR_HA"
    echo "  HAProxy Stats: http://localhost:8404/stats"
fi
echo ""
echo "Root Token: $ROOT_TOKEN"
echo ""

if [ "$TLS" = true ]; then
    echo "TLS Configuration:"
    echo "  export VAULT_ADDR='$VAULT_ADDR'"
    echo "  export VAULT_CACERT=\$PWD/certs/vault-ca.pem"
    echo ""
fi

echo "Default Users:"
echo "  admin    (password: ${VAULT_ADMIN_PASSWORD:-admin-changeme})"
echo "  developer (password: ${VAULT_DEV_PASSWORD:-dev-changeme})"
echo "  cicd     (password: ${VAULT_CICD_PASSWORD:-cicd-changeme})"
echo "  auditor  (password: ${VAULT_AUDITOR_PASSWORD:-auditor-changeme})"
echo ""

echo "Useful commands:"
echo "  ./scripts/cleanup/verify-cluster.sh    # Check cluster health"
echo "  ./scripts/cleanup/cleanup.sh          # Clean up deployment"
echo ""