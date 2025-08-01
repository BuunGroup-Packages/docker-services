#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${1}"
}

error() {
    log "${RED}ERROR: ${1}${NC}"
}

success() {
    log "${GREEN}SUCCESS: ${1}${NC}"
}

info() {
    log "${YELLOW}INFO: ${1}${NC}"
}

create_network_if_not_exists() {
    local network_name=$1
    
    if docker network ls | grep -q " ${network_name} "; then
        info "Network '${network_name}' already exists"
    else
        info "Creating network '${network_name}'..."
        if docker network create "${network_name}"; then
            success "Network '${network_name}' created"
        else
            error "Failed to create network '${network_name}'"
            return 1
        fi
    fi
}

main() {
    info "Initializing Docker networks..."
    
    # Create external networks that services might need
    create_network_if_not_exists "traefik_public"
    
    success "Network initialization complete"
}

main