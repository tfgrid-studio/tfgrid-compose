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

# Read all available IPs from state.yaml (source of truth during deployment)
mycelium_ip=$(grep "^mycelium_address:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}' || echo "")
wireguard_ip=$(grep "^wireguard_address:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}' || echo "")
ipv4_addr=$(grep "^ipv4_address:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}' || echo "")
ipv6_addr=$(grep "^ipv6_address:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}' || echo "")

# Get prefer order from global settings
prefer_list=$(get_global_prefer 2>/dev/null || echo "mycelium,ipv4")

# Select IP based on prefer order
ansible_ip=""
network_type=""

IFS=',' read -ra PREFER_ARRAY <<< "$prefer_list"
for net in "${PREFER_ARRAY[@]}"; do
    net=$(echo "$net" | tr -d ' ')
    case "$net" in
        mycelium)
            if [ -n "$mycelium_ip" ]; then
                ansible_ip="$mycelium_ip"
                network_type="mycelium"
                break
            fi
            ;;
        wireguard)
            if [ -n "$wireguard_ip" ]; then
                ansible_ip="$wireguard_ip"
                network_type="wireguard"
                break
            fi
            ;;
        ipv4)
            if [ -n "$ipv4_addr" ]; then
                ansible_ip="$ipv4_addr"
                network_type="ipv4"
                break
            fi
            ;;
        ipv6)
            if [ -n "$ipv6_addr" ]; then
                ansible_ip="$ipv6_addr"
                network_type="ipv6"
                break
            fi
            ;;
    esac
done

# Fallback: try any available IP if prefer order didn't match
if [ -z "$ansible_ip" ]; then
    if [ -n "$mycelium_ip" ]; then
        ansible_ip="$mycelium_ip"
        network_type="mycelium"
    elif [ -n "$wireguard_ip" ]; then
        ansible_ip="$wireguard_ip"
        network_type="wireguard"
    elif [ -n "$ipv4_addr" ]; then
        ansible_ip="$ipv4_addr"
        network_type="ipv4"
    elif [ -n "$ipv6_addr" ]; then
        ansible_ip="$ipv6_addr"
        network_type="ipv6"
    fi
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
