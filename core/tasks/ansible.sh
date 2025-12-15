#!/usr/bin/env bash
# Task: Run Ansible configuration

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYER_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Get state directory from environment
STATE_DIR="${STATE_DIR:-.tfgrid-compose}"

log_step "Running Ansible configuration..."

# Check if ansible directory exists, if not copy pattern platform
if [ ! -d "$STATE_DIR/ansible" ]; then
    log_info "Copying pattern platform files..."
    
    # Get pattern name from state
    PATTERN_NAME=$(grep "^pattern_name:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')
    
    if [ -z "$PATTERN_NAME" ]; then
        log_error "No pattern_name found in state file"
        exit 1
    fi
    
    PATTERN_PLATFORM_DIR="$DEPLOYER_ROOT/patterns/$PATTERN_NAME/platform"
    
    if [ ! -d "$PATTERN_PLATFORM_DIR" ]; then
        log_error "Pattern platform not found: $PATTERN_PLATFORM_DIR"
        exit 1
    fi
    
    mkdir -p "$STATE_DIR/ansible"
    cp -r "$PATTERN_PLATFORM_DIR"/* "$STATE_DIR/ansible/"
    log_success "Pattern platform copied"
fi

# Save original directory for log paths
ORIG_DIR="$(pwd)"

# Extract variables from state file to pass to Ansible
APP_NAME=$(grep "^app_name:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')
VM_IP=$(grep "^vm_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')
PRIMARY_IP=$(grep "^primary_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')
MYCELIUM_IP=$(grep "^mycelium_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')

# Build extra vars
EXTRA_VARS="app_name=${APP_NAME}"
[ -n "$VM_IP" ] && EXTRA_VARS="$EXTRA_VARS vm_ip=${VM_IP}"
[ -n "$PRIMARY_IP" ] && EXTRA_VARS="$EXTRA_VARS primary_ip=${PRIMARY_IP}"
[ -n "$MYCELIUM_IP" ] && EXTRA_VARS="$EXTRA_VARS mycelium_ip=${MYCELIUM_IP}"

# Run the playbook
cd "$STATE_DIR/ansible" || exit 1

log_info "Configuring VM with Ansible..."
ansible-playbook -i "../inventory.ini" site.yml --extra-vars "$EXTRA_VARS" 2>&1 | tee "../ansible.log"
ANSIBLE_EXIT_CODE=${PIPESTATUS[0]}

cd "$ORIG_DIR"

if [ $ANSIBLE_EXIT_CODE -ne 0 ]; then
    log_error "Ansible failed with exit code $ANSIBLE_EXIT_CODE. Check: $STATE_DIR/ansible.log"
    exit $ANSIBLE_EXIT_CODE
fi

log_success "Platform configured"
