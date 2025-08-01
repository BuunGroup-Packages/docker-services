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

run_cmd() {
    if [ "$EUID" -ne 0 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

setup_docker_group() {
    info "Setting up Docker group..."
    
    if ! getent group docker > /dev/null 2>&1; then
        info "Creating docker group..."
        run_cmd groupadd docker
    else
        info "Docker group already exists"
    fi
}

add_user_to_docker_group() {
    local current_user=""
    
    if [ "$EUID" -eq 0 ]; then
        if [ -n "${SUDO_USER:-}" ]; then
            current_user="$SUDO_USER"
        else
            read -p "Enter username to add to docker group: " current_user
        fi
    else
        current_user="$USER"
    fi
    
    if [ -z "$current_user" ]; then
        error "Could not determine user to add to docker group"
        return 1
    fi
    
    info "Adding user '$current_user' to docker group..."
    
    if id -nG "$current_user" | grep -qw docker; then
        info "User '$current_user' is already in docker group"
    else
        run_cmd usermod -aG docker "$current_user"
        success "User '$current_user' added to docker group"
        info "User will need to log out and back in for changes to take effect"
    fi
}

setup_docker_socket_permissions() {
    info "Setting Docker socket permissions..."
    
    if [ -S /var/run/docker.sock ]; then
        run_cmd chmod 666 /var/run/docker.sock || true
        success "Docker socket permissions updated"
    else
        info "Docker socket not found, will be created when Docker starts"
    fi
}

setup_docker_config_dir() {
    info "Setting up Docker configuration directory..."
    
    if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        local user_home=$(eval echo ~"$SUDO_USER")
    else
        local user_home="$HOME"
    fi
    
    local docker_config_dir="$user_home/.docker"
    
    if [ ! -d "$docker_config_dir" ]; then
        mkdir -p "$docker_config_dir"
        
        if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
            chown "$SUDO_USER:$SUDO_USER" "$docker_config_dir"
        fi
        
        success "Created Docker config directory: $docker_config_dir"
    else
        info "Docker config directory already exists: $docker_config_dir"
    fi
}

configure_docker_daemon() {
    info "Configuring Docker daemon..."
    
    local daemon_json="/etc/docker/daemon.json"
    
    if [ ! -d /etc/docker ]; then
        run_cmd mkdir -p /etc/docker
    fi
    
    if [ ! -f "$daemon_json" ]; then
        info "Creating Docker daemon configuration..."
        
        cat <<EOF | run_cmd tee "$daemon_json" > /dev/null
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "features": {
    "buildkit": true
  }
}
EOF
        success "Docker daemon configuration created"
    else
        info "Docker daemon configuration already exists"
    fi
}

main() {
    info "Setting up Docker user permissions and configuration..."
    
    setup_docker_group
    add_user_to_docker_group
    setup_docker_socket_permissions
    setup_docker_config_dir
    configure_docker_daemon
    
    success "User setup completed"
    
    echo ""
    info "IMPORTANT: If you were added to the docker group, you need to:"
    echo "1. Log out and log back in, OR"
    echo "2. Run: newgrp docker"
    echo ""
}

main