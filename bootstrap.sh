#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/docker-bootstrap-$(date +%Y%m%d-%H%M%S).log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
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

install_docker() {
    info "Installing Docker..."
    
    case $OS in
        ubuntu|debian)
            bash "${SCRIPT_DIR}/scripts/install-docker.sh" "debian"
            ;;
        rhel|centos|fedora|rocky|almalinux)
            bash "${SCRIPT_DIR}/scripts/install-docker.sh" "rhel"
            ;;
        *)
            error "Unsupported OS: $OS"
            echo "Supported OS: Ubuntu, Debian, RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux"
            exit 1
            ;;
    esac
}

setup_user() {
    info "Setting up user permissions..."
    bash "${SCRIPT_DIR}/scripts/setup-user.sh"
}

validate_installation() {
    info "Validating Docker installation..."
    bash "${SCRIPT_DIR}/scripts/validate-environment.sh"
}

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

main() {
    echo "============================================"
    echo "Docker Services Bootstrap Script"
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

trap 'error "Script failed at line $LINENO"' ERR

main "$@"