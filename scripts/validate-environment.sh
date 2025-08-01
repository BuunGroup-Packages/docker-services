#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

log() {
    echo -e "${1}"
}

error() {
    log "${RED}✗ ${1}${NC}"
    ((ERRORS++))
}

success() {
    log "${GREEN}✓ ${1}${NC}"
}

warning() {
    log "${YELLOW}⚠ ${1}${NC}"
    ((WARNINGS++))
}

info() {
    log "${YELLOW}ℹ ${1}${NC}"
}

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

print_summary() {
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

main() {
    echo "Validating Docker environment..."
    echo ""
    
    check_docker_installed
    check_docker_compose
    check_docker_service
    check_docker_permissions
    check_docker_socket
    check_docker_info
    test_docker_run
    check_disk_space
    check_network_connectivity
    
    print_summary
}

main