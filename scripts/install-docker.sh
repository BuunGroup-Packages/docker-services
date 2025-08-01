#!/bin/bash

set -euo pipefail

DISTRO_TYPE=$1

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

install_debian_based() {
    info "Installing Docker on Debian-based system..."
    
    info "Updating package index..."
    run_cmd apt-get update
    
    info "Installing prerequisites..."
    run_cmd apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    info "Adding Docker's official GPG key..."
    run_cmd mkdir -p /etc/apt/keyrings
    
    if [ -f /etc/apt/keyrings/docker.gpg ]; then
        run_cmd rm /etc/apt/keyrings/docker.gpg
    fi
    
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | \
        run_cmd gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    run_cmd chmod a+r /etc/apt/keyrings/docker.gpg
    
    info "Setting up Docker repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
        $(lsb_release -cs) stable" | \
        run_cmd tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    info "Installing Docker Engine, CLI, and plugins..."
    run_cmd apt-get update
    run_cmd apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    
    success "Docker installation completed for Debian-based system"
}

install_rhel_based() {
    info "Installing Docker on RHEL-based system..."
    
    info "Installing prerequisites..."
    run_cmd yum install -y yum-utils
    
    info "Setting up Docker repository..."
    local repo_url=""
    
    if [ -f /etc/redhat-release ]; then
        if grep -qi "centos" /etc/redhat-release; then
            repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
        elif grep -qi "rhel" /etc/redhat-release; then
            repo_url="https://download.docker.com/linux/rhel/docker-ce.repo"
        elif grep -qi "fedora" /etc/redhat-release; then
            repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"
        fi
    fi
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            rocky|almalinux)
                repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
                ;;
            fedora)
                repo_url="https://download.docker.com/linux/fedora/docker-ce.repo"
                ;;
        esac
    fi
    
    if [ -z "$repo_url" ]; then
        repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
    fi
    
    run_cmd yum-config-manager --add-repo "$repo_url"
    
    info "Installing Docker Engine, CLI, and plugins..."
    run_cmd yum install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    
    success "Docker installation completed for RHEL-based system"
}

enable_and_start_docker() {
    info "Enabling and starting Docker service..."
    
    run_cmd systemctl enable docker.service
    run_cmd systemctl enable containerd.service
    run_cmd systemctl start docker.service
    run_cmd systemctl start containerd.service
    
    if run_cmd systemctl is-active --quiet docker; then
        success "Docker service is running"
    else
        error "Failed to start Docker service"
        exit 1
    fi
}

main() {
    case $DISTRO_TYPE in
        debian)
            install_debian_based
            ;;
        rhel)
            install_rhel_based
            ;;
        *)
            error "Unknown distribution type: $DISTRO_TYPE"
            exit 1
            ;;
    esac
    
    enable_and_start_docker
}

main