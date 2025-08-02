#!/bin/bash

# Fix Redis memory overcommit warning
echo "Fixing Redis memory overcommit warning..."

# Check current value
current_value=$(sysctl -n vm.overcommit_memory)
echo "Current vm.overcommit_memory value: $current_value"

if [ "$current_value" != "1" ]; then
    echo "Setting vm.overcommit_memory = 1"
    
    # Apply immediately
    sudo sysctl vm.overcommit_memory=1
    
    # Make it persistent
    if ! grep -q "vm.overcommit_memory = 1" /etc/sysctl.conf; then
        echo "vm.overcommit_memory = 1" | sudo tee -a /etc/sysctl.conf
        echo "Added to /etc/sysctl.conf for persistence"
    fi
    
    echo "Redis memory overcommit fixed!"
else
    echo "vm.overcommit_memory is already set to 1"
fi