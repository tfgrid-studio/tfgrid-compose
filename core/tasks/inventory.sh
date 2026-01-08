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

# Get app name from state file
APP_NAME=$(grep "^app_name:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')

# Use network-aware IP selection that respects global preferences (prefer order)
# get_preferred_ip returns "ip|network_type" format
preferred_result=$(get_preferred_ip "$DEPLOYMENT_ID" 2>/dev/null || echo "")

if [ -n "$preferred_result" ]; then
    ansible_ip=$(echo "$preferred_result" | cut -d'|' -f1)
    network_type=$(echo "$preferred_result" | cut -d'|' -f2)
else
    # Fallback to legacy get_deployment_ip
    ansible_ip=$(get_deployment_ip "$DEPLOYMENT_ID" 2>/dev/null || echo "")
    network_type="unknown"
fi

if [ -z "$ansible_ip" ]; then
    log_error "No IP available for Ansible. Check provisioned networks."
    exit 1
fi

# Format network type for logging
case "$network_type" in
    "mycelium") network_type_display="Mycelium (IPv6)" ;;
    "wireguard") network_type_display="WireGuard (private)" ;;
    "ipv4") network_type_display="Public IPv4" ;;
    "ipv6") network_type_display="Public IPv6" ;;
    *) network_type_display="$network_type" ;;
esac

log_info "Ansible will use: $network_type_display ($ansible_ip)"

# Format IP for Ansible (IPv6 addresses use brackets for specific use cases, but SSH connection doesn't need them)
ansible_host="$ansible_ip"

# Create inventory file using network-preferred IP
cat > "$STATE_DIR/inventory.ini" << EOF
# Auto-generated Ansible inventory for $APP_NAME
# Network: $network_type_display

[all]
$APP_NAME ansible_host=$ansible_host ansible_user=root ansible_connection=ssh ansible_ssh_extra_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=30'

[app]
$APP_NAME
EOF

log_success "Ansible inventory generated ($network_type_display)"
