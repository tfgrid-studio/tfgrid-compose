#!/usr/bin/env bash
# Pattern script to show IP addresses

set -e

# Get state directory (use global state if not set)
STATE_DIR="${STATE_DIR:-$STATE_BASE_DIR/$APP_NAME}"

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
    PRIMARY_IP=$(grep "primary_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}' 2>/dev/null)
    PRIMARY_IP_TYPE=$(grep "primary_ip_type:" "$STATE_DIR/state.yaml" | awk '{print $2}' 2>/dev/null)
    MYCELIUM_IP=$(grep "mycelium_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}' 2>/dev/null || echo "N/A")
    
    echo "VM IP:        $VM_IP"
    
    # Display WireGuard IP (same as primary_ip when primary_ip_type is wireguard)
    if [ "$PRIMARY_IP_TYPE" = "wireguard" ]; then
        echo "Wireguard IP: $PRIMARY_IP"
    else
        echo "Wireguard IP: N/A"
    fi
    
    echo "Mycelium IP:  $MYCELIUM_IP"
    echo ""
    echo "SSH: ssh root@$VM_IP"
fi
