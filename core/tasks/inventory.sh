#!/usr/bin/env bash
# Task: Generate Ansible inventory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Get state directory from environment
STATE_DIR="${STATE_DIR:-.tfgrid-compose}"

log_step "Generating Ansible inventory..."

# Get app name and VM IP from state file (source of truth)
APP_NAME=$(grep "^app_name:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')
vm_ip=$(grep "^vm_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')

if [ -z "$vm_ip" ]; then
    log_error "No VM IP found in state"
    exit 1
fi

# Create inventory file
cat > "$STATE_DIR/inventory.ini" << EOF
# Auto-generated Ansible inventory for $APP_NAME

[all]
$APP_NAME ansible_host=$vm_ip ansible_user=root ansible_ssh_extra_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR'

[app]
$APP_NAME
EOF

log_success "Ansible inventory generated"
