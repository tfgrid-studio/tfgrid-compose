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

# Get VM IPs from state
VM_IP=$(grep "vm_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}')
MYCELIUM_IP=$(grep "mycelium_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}')
PRIMARY_IP_TYPE=$(grep "primary_ip_type:" "$STATE_DIR/state.yaml" | awk '{print $2}')

if [ -z "$VM_IP" ]; then
    echo "❌ Could not read VM IP from state"
    exit 1
fi

# Determine which IP to use
CONNECT_IP="$VM_IP"
CONNECT_METHOD="$PRIMARY_IP_TYPE"

# If using WireGuard, check connection and reconnect if needed
if [ "$PRIMARY_IP_TYPE" = "wireguard" ]; then
    WG_CONF="$STATE_DIR/wg.conf"
    
    # Check if can reach VM
    if ! ping -c 1 -W 2 "$VM_IP" &>/dev/null; then
        echo "⚠️  WireGuard connection appears down, attempting reconnect..."
        
        # Determine interface name - use wg1 for tfgrid-compose
        WG_INTERFACE="wg1"
        
        # Stop existing interface (try both wg-quick down and manual removal)
        sudo wg-quick down "$WG_INTERFACE" 2>/dev/null || true
        sudo ip link delete "$WG_INTERFACE" 2>/dev/null || true
        
        # Start WireGuard with fresh config
        if ! sudo wg-quick up "$WG_CONF" 2>/dev/null; then
            echo "⚠️  WireGuard reconnect failed"
            # Continue to try Mycelium fallback
        fi
        
        # Wait for connection
        sleep 2
        
        # Verify connectivity
        if ! ping -c 1 -W 2 "$VM_IP" &>/dev/null; then
            echo "⚠️  VM not reachable via WireGuard"
            
            # Try Mycelium as fallback
            if [ -n "$MYCELIUM_IP" ]; then
                echo "🔄 Falling back to Mycelium network..."
                CONNECT_IP="$MYCELIUM_IP"
                CONNECT_METHOD="mycelium"
                
                # Test Mycelium connectivity
                if ! ping6 -c 1 -W 2 "$MYCELIUM_IP" &>/dev/null; then
                    echo "❌ VM not reachable via Mycelium either"
                    echo ""
                    echo "Troubleshooting:"
                    echo "  1. VM may still be booting (wait 30-60 seconds)"
                    echo "  2. Check VM status: tfgrid-compose logs tfgrid-ai-agent"
                    echo "  3. Try WireGuard: sudo wg-quick up $WG_CONF"
                    echo "  4. Try Mycelium: ssh root@[$MYCELIUM_IP]"
                    exit 1
                fi
                
                echo "✅ Mycelium connection available"
            else
                echo "❌ Cannot reach VM and no Mycelium IP available"
                exit 1
            fi
        else
            echo "✅ WireGuard reconnected"
        fi
    fi
fi

# Format IP for SSH (add brackets for IPv6)
if [[ "$CONNECT_IP" == *":"* ]]; then
    # IPv6 address (Mycelium)
    SSH_TARGET="root@[$CONNECT_IP]"
else
    # IPv4 address (WireGuard)
    SSH_TARGET="root@$CONNECT_IP"
fi

echo "🔌 Connecting via $CONNECT_METHOD to $CONNECT_IP..."
echo ""

# SSH into VM
ssh -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    $SSH_TARGET
