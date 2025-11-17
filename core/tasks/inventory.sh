#!/usr/bin/env bash
# Task: Generate Ansible inventory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"
source "$SCRIPT_DIR/../network.sh"

# Get state directory from environment
STATE_DIR="${STATE_DIR:-.tfgrid-compose}"
DEPLOYMENT_ID=$(basename "$STATE_DIR")

log_step "Generating Ansible inventory..."

# Get app name and IPs from state file (source of truth)
APP_NAME=$(grep "^app_name:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')
vm_ip=$(grep "^vm_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')

if [ -z "$vm_ip" ]; then
    log_error "No VM IP found in state"
    exit 1
fi

# Use network-aware IP selection that respects global preferences
ansible_ip=$(get_deployment_ip "$DEPLOYMENT_ID")

# Determine network type for logging
network_preference=$(get_network_preference "$DEPLOYMENT_ID")
case "$network_preference" in
    "mycelium")
        network_type="Mycelium (IPv6)"
        ;;
    *)
        network_type="WireGuard (IPv4)"
        ;;
esac

log_info "Ansible will use: $network_type connection"

if [ -z "$ansible_ip" ]; then
    log_error "No IP available for Ansible based on network preference: $network_preference"
    exit 1
fi

# Format IP for Ansible (add brackets for IPv6)
if [[ "$ansible_ip" == *":"* ]]; then
    # IPv6 address (Mycelium)
    ansible_host="[$ansible_ip]"
else
    # IPv4 address (WireGuard)
    ansible_host="$ansible_ip"
fi

# Create inventory file using network-preferred IP
cat > "$STATE_DIR/inventory.ini" << EOF
# Auto-generated Ansible inventory for $APP_NAME
# Network preference: $network_preference ($network_type)

[all]
$APP_NAME ansible_host=$ansible_host ansible_user=root ansible_ssh_extra_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR'

[app]
$APP_NAME
EOF

log_success "Ansible inventory generated with $network_type connection"
