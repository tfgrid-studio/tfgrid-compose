#!/bin/bash
# Pattern script to SSH

set -e

# Get state directory (use global state if not set)
STATE_DIR="${STATE_DIR:-$STATE_BASE_DIR/$APP_NAME}"

# Read deployment info
if [ ! -f "$STATE_DIR/state.yaml" ]; then
    echo "❌ No deployment found. Run 'tfgrid-compose up' first."
    exit 1
fi

# Get VM IP and network type from state
VM_IP=$(grep "vm_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}')
PRIMARY_IP_TYPE=$(grep "primary_ip_type:" "$STATE_DIR/state.yaml" | awk '{print $2}')

if [ -z "$VM_IP" ]; then
    echo "❌ Could not read VM IP from state"
    exit 1
fi

# If using WireGuard, check connection and reconnect if needed
if [ "$PRIMARY_IP_TYPE" = "wireguard" ]; then
    WG_CONF="$STATE_DIR/wg.conf"
    
    # Check if can reach VM
    if ! ping -c 1 -W 2 "$VM_IP" &>/dev/null; then
        echo "⚠️  WireGuard connection appears down, reconnecting..."
        
        # Find WireGuard interface name from config
        WG_INTERFACE=$(grep "^\[Interface\]" -A 10 "$WG_CONF" | grep -v "^\[" | head -1 | awk '{print "wg1"}')
        WG_INTERFACE=${WG_INTERFACE:-wg1}
        
        # Stop existing interface
        sudo wg-quick down "$WG_INTERFACE" 2>/dev/null || true
        
        # Start WireGuard
        sudo wg-quick up "$WG_CONF" 2>/dev/null || {
            echo "❌ Failed to establish WireGuard connection"
            echo "Try manually: sudo wg-quick up $WG_CONF"
            exit 1
        }
        
        # Wait for connection
        sleep 2
        
        # Verify connectivity
        if ! ping -c 1 -W 2 "$VM_IP" &>/dev/null; then
            echo "❌ Cannot reach VM after WireGuard reconnect"
            exit 1
        fi
        
        echo "✅ WireGuard reconnected"
    fi
fi

echo "🔌 Connecting to $VM_IP..."
echo ""

# SSH into VM
ssh -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    root@$VM_IP
