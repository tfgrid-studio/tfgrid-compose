#!/bin/bash
set -e

# Get script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEPLOYMENT_DIR="$SCRIPT_DIR/../infrastructure"

# Get management node WireGuard IP from Terraform output
MANAGEMENT_IP=$(tofu -chdir="$DEPLOYMENT_DIR" output -raw management_node_wireguard_ip)

if [ -z "$MANAGEMENT_IP" ]; then
    echo "Error: Could not retrieve management node IP."
    exit 1
fi

echo "Connecting to management node ($MANAGEMENT_IP) and launching K9s..."
ssh -t root@"$MANAGEMENT_IP" "k9s"
