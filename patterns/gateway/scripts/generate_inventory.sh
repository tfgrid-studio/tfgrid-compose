#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
INFRASTRUCTURE_DIR="$PROJECT_DIR/infrastructure"
PLATFORM_DIR="$PROJECT_DIR/platform"

# Load configuration from .env file if it exists
if [[ -f "$PROJECT_DIR/.env" ]]; then
    source "$PROJECT_DIR/.env"
fi

# Use variables with fallbacks
MAIN_NETWORK="${MAIN_NETWORK:-wireguard}"
NETWORK_MODE="${NETWORK_MODE:-wireguard-only}"
GATEWAY_TYPE="${GATEWAY_TYPE:-gateway_nat}"
INTER_NODE_NETWORK="${INTER_NODE_NETWORK:-wireguard}"

echo -e "${GREEN}Generating Ansible inventory from Terraform outputs${NC}"
if [[ -f "$PROJECT_DIR/.env" ]]; then
    echo -e "${YELLOW}Loading configuration from .env file${NC}"
fi
echo -e "${YELLOW}Using MAIN_NETWORK: ${MAIN_NETWORK}${NC}"
echo -e "${YELLOW}Using NETWORK_MODE: ${NETWORK_MODE}${NC}"
echo -e "${YELLOW}Using GATEWAY_TYPE: ${GATEWAY_TYPE}${NC}"
echo -e "${YELLOW}Using INTER_NODE_NETWORK: ${INTER_NODE_NETWORK}${NC}"

# Check if Terraform state exists
if [[ ! -f "$INFRASTRUCTURE_DIR/terraform.tfstate" ]]; then
    echo -e "${RED}ERROR: Terraform state not found. Run infrastructure deployment first.${NC}"
    exit 1
fi

cd "$INFRASTRUCTURE_DIR"

# Get Terraform outputs
echo -e "${YELLOW}Fetching Terraform outputs...${NC}"

GATEWAY_PUBLIC_IP=$(tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||' || echo "")
GATEWAY_WIREGUARD_IP=$(tofu output -json gateway_wireguard_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||' || echo "")
GATEWAY_MYCELIUM_IP=$(tofu output -json gateway_mycelium_ip 2>/dev/null | jq -r . 2>/dev/null || echo "")
TFGRID_NETWORK=$(tofu output -json tfgrid_network 2>/dev/null | jq -r . 2>/dev/null || echo "test")

INTERNAL_WIREGUARD_IPS=$(tofu output -json internal_wireguard_ips 2>/dev/null || echo "{}")
INTERNAL_MYCELIUM_IPS=$(tofu output -json internal_mycelium_ips 2>/dev/null || echo "{}")

# Generate inventory file
INVENTORY_FILE="$PLATFORM_DIR/inventory.ini"

# Determine gateway ansible_host based on MAIN_NETWORK
if [[ "$MAIN_NETWORK" == "public" ]]; then
    GATEWAY_ANSIBLE_HOST=${GATEWAY_PUBLIC_IP}
elif [[ "$MAIN_NETWORK" == "wireguard" ]]; then
    GATEWAY_ANSIBLE_HOST=${GATEWAY_WIREGUARD_IP}
else # mycelium
    GATEWAY_ANSIBLE_HOST=${GATEWAY_MYCELIUM_IP}
fi

cat > "$INVENTORY_FILE" << EOF
[all:vars]
ansible_user=root
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

[gateway]
gateway ansible_host=${GATEWAY_ANSIBLE_HOST} wireguard_ip=${GATEWAY_WIREGUARD_IP} mycelium_ip=${GATEWAY_MYCELIUM_IP} internal_ip=${GATEWAY_WIREGUARD_IP}

[internal]
EOF

# Add internal VMs with port assignments
echo "$INTERNAL_WIREGUARD_IPS" | jq -r 'to_entries | sort_by(.key | tonumber) | to_entries[] | "\(.value.key) wireguard_ip=\(.value.value) vm_port=\(8001 + .key) vm_id=\(.value.key)"' | \
while IFS= read -r line; do
    vm_id=$(echo "$line" | awk '{print $1}')
    wireguard_ip=$(echo "$line" | awk -F'=' '{print $2}' | awk '{print $1}')
    mycelium_ip=$(echo "$INTERNAL_MYCELIUM_IPS" | jq -r ".\"$vm_id\"")

    # Set internal_ip based on INTER_NODE_NETWORK
    if [[ "$INTER_NODE_NETWORK" == "wireguard" ]]; then
        internal_ip=$wireguard_ip
    else
        internal_ip=$mycelium_ip
    fi

    if [[ "$MAIN_NETWORK" == "mycelium" ]]; then
        # Use mycelium IP for ansible_host
        echo "$vm_id ansible_host=$mycelium_ip wireguard_ip=$wireguard_ip mycelium_ip=$mycelium_ip internal_ip=$internal_ip vm_port=$(echo "$line" | awk -F'vm_port=' '{print $2}' | awk '{print $1}') vm_id=$vm_id" >> "$INVENTORY_FILE"
    else
        # Use wireguard IP for ansible_host (default, since public not applicable for internal)
        echo "$vm_id ansible_host=$wireguard_ip wireguard_ip=$wireguard_ip mycelium_ip=$mycelium_ip internal_ip=$internal_ip vm_port=$(echo "$line" | awk -F'vm_port=' '{print $2}' | awk '{print $1}') vm_id=$vm_id" >> "$INVENTORY_FILE"
    fi
done

# Internal variables section removed - mycelium IPs are now included in each host line

# Create group variables
mkdir -p "$PLATFORM_DIR/group_vars"

# Gateway group variables
cat > "$PLATFORM_DIR/group_vars/gateway.yml" << EOF
---
# Gateway configuration
gateway_type: "{{ lookup('env', 'GATEWAY_TYPE') | default('gateway_nat', true) }}"

# Network configuration
network_mode: "$NETWORK_MODE"

# Port forwarding (for NAT gateway)
port_forwards: []

# Proxy configuration (for proxy gateway)
proxy_ports: [8080, 8443]
udp_ports: []
enable_ssl: false
domain_name: ""
ssl_email: ""

# Testing
enable_testing: false
EOF

# Internal group variables
cat > "$PLATFORM_DIR/group_vars/internal.yml" << EOF
---
# Internal VM configuration
services:
  - name: web
    port: 80
    type: http
  - name: api
    port: 8080
    type: tcp
EOF

# All group variables
cat > "$PLATFORM_DIR/group_vars/all.yml" << EOF
---
# Global configuration
ansible_python_interpreter: /usr/bin/python3

# Network configuration
network_cidr: "10.1.0.0/16"
wireguard_port: 51820
network_mode: "{{ lookup('env', 'NETWORK_MODE') | default('wireguard-only', true) }}"
disable_port_forwarding: "{{ lookup('env', 'DISABLE_PORT_FORWARDING') | default('false', true) | lower }}"
gateway_type: "{{ lookup('env', 'GATEWAY_TYPE') | default('gateway_nat', true) }}"

# ThreeFold Grid network
tfgrid_network: "$TFGRID_NETWORK"

# Mycelium configuration
mycelium_enabled: true
EOF

echo -e "${GREEN}Inventory generated successfully!${NC}"
echo "Inventory file: $INVENTORY_FILE"
echo "Main network (Ansible): $MAIN_NETWORK"
echo "Inter-node network: $INTER_NODE_NETWORK"
echo "Network mode (Website): $NETWORK_MODE"
echo ""
echo -e "${YELLOW}Available gateway types:${NC}"
echo "  - gateway_nat: NAT-based gateway with nftables"
echo "  - gateway_proxy: Proxy-based gateway with HAProxy/Nginx"
echo ""
echo -e "${YELLOW}Available network types (Ansible connectivity):${NC}"
echo "  - public: Use public IP for gateway Ansible connectivity (internal uses wireguard/mycelium)"
echo "  - wireguard: Use WireGuard VPN for Ansible connectivity (default)"
echo "  - mycelium: Use Mycelium IPv6 overlay for Ansible connectivity"
echo ""
echo -e "${YELLOW}Available inter-node networks:${NC}"
echo "  - wireguard: Use WireGuard for node-to-node communication (default)"
echo "  - mycelium: Use Mycelium for node-to-node communication"
echo ""
echo -e "${YELLOW}Available network modes (Website hosting):${NC}"
echo "  - wireguard-only: Websites on WireGuard only (default)"
echo "  - mycelium-only: Websites on Mycelium only"
echo "  - both: Websites on both networks (redundancy)"
echo ""
echo -e "${YELLOW}To use a specific gateway type:${NC}"
echo "  export GATEWAY_TYPE=gateway_proxy"
echo "  ansible-playbook -i platform/inventory.ini platform/site.yml"
echo ""
echo -e "${YELLOW}To configure network settings:${NC}"
echo "  export MAIN_NETWORK=public"
echo "  export INTER_NODE_NETWORK=mycelium"
echo "  export NETWORK_MODE=both"
echo "  make inventory"