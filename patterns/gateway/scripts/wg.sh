#!/usr/bin/env bash
set -euo pipefail

# Check dependencies
command -v jq >/dev/null 2>&1 || {
    echo >&2 "ERROR: jq required but not found. Install with:
    sudo apt install jq || brew install jq";
    exit 1;
}

command -v tofu >/dev/null 2>&1 || {
    echo >&2 "ERROR: tofu (OpenTofu) required but not found.";
    exit 1;
}

command -v wg-quick >/dev/null 2>&1 || {
    echo >&2 "ERROR: wg-quick required but not found. Install WireGuard with:
    sudo apt install wireguard";
    exit 1;
}

# Get script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEPLOYMENT_DIR="$SCRIPT_DIR/../infrastructure"

# Fetch IP addresses and WireGuard config from Terraform outputs
echo "Fetching IP addresses and WireGuard config from Terraform..."
terraform_output=$(tofu -chdir="$DEPLOYMENT_DIR" show -json)

# Extract WireGuard configuration
wg_config=$(jq -r '.values.outputs.wg_config.value' <<< "$terraform_output")

# Write WireGuard configuration to a file
WG_CONFIG_FILE="/etc/wireguard/gateway.conf"
echo "$wg_config" | sudo tee "$WG_CONFIG_FILE" > /dev/null

# Bring down the WireGuard interface if it's up
sudo wg-quick down gateway 2>/dev/null || true

# Bring up the WireGuard interface
sudo wg-quick up gateway

# Remove known_hosts to avoid SSH key conflicts
sudo rm -f ~/.ssh/known_hosts

echo "WireGuard setup completed!"
echo "Gateway VM WireGuard IP: $(jq -r '.values.outputs.gateway_wireguard_ip.value' <<< "$terraform_output")"
echo "Internal VM WireGuard IPs: $(jq -r '.values.outputs.internal_wireguard_ips.value' <<< "$terraform_output")"