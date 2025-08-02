#!/bin/bash

set -euo pipefail

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/docker-bootstrap-$(date +%Y%m%d-%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters for validation
ERRORS=0
WARNINGS=0

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

error() {
    log "${RED}ERROR: ${1}${NC}"
    ((ERRORS++)) || true
}

success() {
    log "${GREEN}SUCCESS: ${1}${NC}"
}

warning() {
    log "${YELLOW}WARNING: ${1}${NC}"
    ((WARNINGS++)) || true
}

info() {
    log "${YELLOW}INFO: ${1}${NC}"
}

# Helper to run commands with sudo if needed
run_cmd() {
    if [ "$EUID" -ne 0 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

# OS Detection
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        VER=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        OS=$(echo $DISTRIB_ID | tr '[:upper:]' '[:lower:]')
        VER=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        OS=debian
        VER=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        OS=rhel
        VER=$(rpm -q --qf "%{VERSION}" $(rpm -qf /etc/redhat-release))
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
    
    info "Detected OS: $OS $VER"
}

# Prerequisites check
check_prerequisites() {
    info "Checking prerequisites..."
    
    if [ "$EUID" -ne 0 ] && ! command -v sudo &> /dev/null; then
        error "This script must be run as root or with sudo available"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        error "Either curl or wget is required but not installed"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Docker installation for Debian-based systems
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

# Docker installation for RHEL-based systems
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
        case "$ID" in
            rocky|almalinux)
                repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
                ;;
        esac
    fi
    
    if [ -z "$repo_url" ]; then
        repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
    fi
    
    run_cmd yum-config-manager --add-repo "$repo_url"
    
    info "Installing Docker Engine, CLI, and plugins..."
    run_cmd yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    success "Docker installation completed for RHEL-based system"
}

# Main Docker installation function
install_docker() {
    info "Installing Docker..."
    
    case $OS in
        ubuntu|debian)
            install_debian_based
            ;;
        rhel|centos|fedora|rocky|almalinux)
            install_rhel_based
            ;;
        *)
            error "Unsupported OS: $OS"
            echo "Supported OS: Ubuntu, Debian, RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux"
            exit 1
            ;;
    esac
    
    # Start and enable Docker service
    info "Starting Docker service..."
    run_cmd systemctl start docker
    run_cmd systemctl enable docker
    success "Docker service started and enabled"
}

# Setup Docker group and permissions
setup_docker_group() {
    info "Setting up Docker group..."
    
    if ! getent group docker > /dev/null 2>&1; then
        info "Creating docker group..."
        run_cmd groupadd docker
    else
        info "Docker group already exists"
    fi
}

# Add user to Docker group
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

# Setup Docker socket permissions
setup_docker_socket_permissions() {
    info "Setting Docker socket permissions..."
    
    if [ -S /var/run/docker.sock ]; then
        run_cmd chmod 666 /var/run/docker.sock || true
        success "Docker socket permissions updated"
    else
        info "Docker socket not found, will be created when Docker starts"
    fi
}

# Setup Docker configuration directory
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

# Configure Docker daemon
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

# User setup main function
setup_user() {
    info "Setting up user permissions..."
    
    setup_docker_group
    add_user_to_docker_group
    setup_docker_socket_permissions
    setup_docker_config_dir
    configure_docker_daemon
    
    success "User setup completed"
}

# Validation functions
check_docker_installed() {
    info "Checking Docker installation..."
    
    if command -v docker &> /dev/null; then
        local version=$(docker --version)
        success "Docker is installed: $version"
    else
        error "Docker is not installed or not in PATH"
        return 1
    fi
}

check_docker_compose() {
    info "Checking Docker Compose installation..."
    
    if docker compose version &> /dev/null; then
        local version=$(docker compose version)
        success "Docker Compose is installed: $version"
    else
        error "Docker Compose plugin is not installed"
        return 1
    fi
}

check_docker_service() {
    info "Checking Docker service status..."
    
    if systemctl is-active --quiet docker; then
        success "Docker service is active"
    else
        error "Docker service is not running"
        echo "  Try: sudo systemctl start docker"
        return 1
    fi
    
    if systemctl is-enabled --quiet docker; then
        success "Docker service is enabled (will start on boot)"
    else
        warning "Docker service is not enabled"
        echo "  Try: sudo systemctl enable docker"
    fi
}

check_docker_permissions() {
    info "Checking Docker permissions..."
    
    if [ "$EUID" -eq 0 ]; then
        success "Running as root, Docker commands will work"
    else
        if groups | grep -q docker; then
            success "Current user is in docker group"
            
            if docker ps &> /dev/null; then
                success "Docker commands work without sudo"
            else
                warning "User is in docker group but Docker commands require sudo"
                echo "  You may need to log out and back in for group changes to take effect"
            fi
        else
            warning "Current user is not in docker group"
            echo "  Docker commands will require sudo"
            echo "  To fix: sudo usermod -aG docker $USER"
        fi
    fi
}

check_docker_socket() {
    info "Checking Docker socket..."
    
    if [ -S /var/run/docker.sock ]; then
        success "Docker socket exists"
        
        if [ -r /var/run/docker.sock ] && [ -w /var/run/docker.sock ]; then
            success "Docker socket is accessible"
        else
            warning "Docker socket exists but may not be fully accessible"
        fi
    else
        error "Docker socket not found at /var/run/docker.sock"
    fi
}

check_docker_info() {
    info "Checking Docker system information..."
    
    if docker info &> /dev/null; then
        success "Docker daemon is responsive"
        
        local storage_driver=$(docker info 2>/dev/null | grep "Storage Driver:" | awk '{print $3}')
        if [ -n "$storage_driver" ]; then
            info "Storage driver: $storage_driver"
        fi
        
        local cgroup_version=$(docker info 2>/dev/null | grep "Cgroup Version:" | awk '{print $3}')
        if [ -n "$cgroup_version" ]; then
            info "Cgroup version: $cgroup_version"
        fi
    else
        error "Cannot connect to Docker daemon"
        echo "  Is the Docker daemon running?"
    fi
}

test_docker_run() {
    info "Testing Docker container run..."
    
    if docker run --rm hello-world &> /dev/null; then
        success "Successfully ran test container"
    else
        error "Failed to run test container"
        echo "  This might indicate networking or registry access issues"
    fi
}

check_disk_space() {
    info "Checking disk space..."
    
    local docker_root="/var/lib/docker"
    if [ -d "$docker_root" ]; then
        local available=$(df -BG "$docker_root" | awk 'NR==2 {print $4}' | sed 's/G//')
        if [ "$available" -lt 10 ]; then
            warning "Low disk space: ${available}GB available in $docker_root"
            echo "  Docker requires adequate disk space for images and containers"
        else
            success "Adequate disk space: ${available}GB available"
        fi
    fi
}

check_network_connectivity() {
    info "Checking network connectivity to Docker Hub..."
    
    if curl -s -o /dev/null -w "%{http_code}" https://hub.docker.com | grep -q "200\|301\|302"; then
        success "Can reach Docker Hub"
    else
        warning "Cannot reach Docker Hub"
        echo "  This might cause issues pulling images"
    fi
}

# Main validation function
validate_installation() {
    info "Validating Docker installation..."
    echo ""
    
    # Reset counters
    ERRORS=0
    WARNINGS=0
    
    check_docker_installed
    check_docker_compose
    check_docker_service
    check_docker_permissions
    check_docker_socket
    check_docker_info
    test_docker_run
    check_disk_space
    check_network_connectivity
    
    echo ""
    echo "========================================"
    echo "Docker Environment Validation Summary"
    echo "========================================"
    echo ""
    
    if [ $ERRORS -eq 0 ]; then
        if [ $WARNINGS -eq 0 ]; then
            success "All checks passed! Docker is ready to use."
        else
            success "Docker is functional with $WARNINGS warning(s)."
        fi
    else
        error "Found $ERRORS error(s) and $WARNINGS warning(s)."
        echo ""
        echo "Please fix the errors before using Docker."
    fi
    
    echo ""
    return $ERRORS
}

# Display next steps
display_next_steps() {
    echo ""
    success "Docker installation completed successfully!"
    echo ""
    info "Next steps:"
    echo "1. Log out and log back in for group changes to take effect"
    echo "2. Test Docker: docker run hello-world"
    echo "3. Test Docker Compose: docker compose version"
    echo "4. Deploy services from the services/ directory"
    echo ""
    info "Example usage:"
    echo "   cd services/databases/postgres"
    echo "   cp .env.example .env"
    echo "   # Edit .env with your values"
    echo "   docker compose up -d"
    echo ""
    info "Installation log saved to: ${LOG_FILE}"
}

# Main function
main() {
    echo "============================================"
    echo "Docker Services Bootstrap Script (Integrated)"
    echo "============================================"
    echo ""
    
    info "Starting Docker installation process..."
    info "Log file: ${LOG_FILE}"
    echo ""
    
    detect_os
    check_prerequisites
    
    if command -v docker &> /dev/null; then
        info "Docker is already installed"
        docker --version
        
        read -p "Do you want to reinstall Docker? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Skipping Docker installation"
        else
            install_docker
        fi
    else
        install_docker
    fi
    
    setup_user
    validate_installation
    display_next_steps
}

# Error handling
trap 'error "Script failed at line $LINENO"' ERR

# Run main function
main "$@"