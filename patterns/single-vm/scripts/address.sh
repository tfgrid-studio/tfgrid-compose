#!/usr/bin/env bash
# Pattern script to show IP addresses

set -e

# Get state directory
STATE_DIR=".tfgrid-compose"

# Read deployment info
if [ ! -f "$STATE_DIR/state.yaml" ]; then
    echo "❌ No deployment found. Run 'tfgrid-compose up' first."
    exit 1
fi

echo "📍 Deployment Addresses:"
echo ""

# Read and display all IPs from state
if [ -f "$STATE_DIR/state.yaml" ]; then
    VM_IP=$(grep "vm_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}')
    WIREGUARD_IP=$(grep "wireguard_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}' 2>/dev/null || echo "N/A")
    MYCELIUM_IP=$(grep "mycelium_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}' 2>/dev/null || echo "N/A")
    
    echo "VM IP:        $VM_IP"
    echo "Wireguard IP: $WIREGUARD_IP"
    echo "Mycelium IP:  $MYCELIUM_IP"
    echo ""
    echo "SSH: ssh root@$VM_IP"
fi
