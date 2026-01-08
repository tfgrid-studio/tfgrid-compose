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

# Get deployment ID from STATE_DIR path
DEPLOYMENT_ID=$(basename "$STATE_DIR")

# Source network functions for preference lookup
# NOTE: use a simple, robust path computation to avoid nested command
# substitution parsing issues on some shells
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../.. && pwd)"
source "$SCRIPT_DIR/core/common.sh"
source "$SCRIPT_DIR/core/network.sh"

# Get VM IPs from state
VM_IP=$(grep "ipv4_address:" "$STATE_DIR/state.yaml" | awk '{print $2}')
MYCELIUM_IP=$(grep "mycelium_address:" "$STATE_DIR/state.yaml" | awk '{print $2}')
PRIMARY_IP_TYPE=$(grep "primary_ip_type:" "$STATE_DIR/state.yaml" | awk '{print $2}')

if [ -z "$VM_IP" ]; then
    echo "❌ Could not read VM IP from state"
    exit 1
fi

# Use network-aware IP selection (respects global preference)
PREFERRED_NETWORK=$(get_network_preference "$DEPLOYMENT_ID")

# Determine connection method based on preference
case "$PREFERRED_NETWORK" in
    "mycelium")
        if [ -n "$MYCELIUM_IP" ]; then
            CONNECT_IP="$MYCELIUM_IP"
            CONNECT_METHOD="mycelium"
        else
            if [ "$PRIMARY_IP_TYPE" = "public" ] && [ -n "$VM_IP" ]; then
                echo "⚠️  Mycelium preferred but IP not available, using public IPv4"
                CONNECT_IP="$VM_IP"
                CONNECT_METHOD="public"
            else
                echo "⚠️  Mycelium preferred but IP not available, using WireGuard"
                CONNECT_IP="$VM_IP"
                CONNECT_METHOD="wireguard"
            fi
        fi
        ;;
    *)
        if [ "$PRIMARY_IP_TYPE" = "public" ] && [ -n "$VM_IP" ]; then
            CONNECT_IP="$VM_IP"
            CONNECT_METHOD="public"
        else
            CONNECT_IP="$VM_IP"
            CONNECT_METHOD="wireguard"
        fi
        ;;
esac

# Check connectivity to selected IP and fallback to alternative network if needed
if [ "$CONNECT_METHOD" = "wireguard" ]; then
    WG_CONF="$STATE_DIR/wg.conf"

    # Check if can reach VM via WireGuard
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

            # Try Mycelium as fallback if available
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
elif [ "$CONNECT_METHOD" = "mycelium" ]; then
    # Check if can reach VM via Mycelium
    if ! ping6 -c 1 -W 2 "$MYCELIUM_IP" &>/dev/null; then
        echo "⚠️  VM not reachable via Mycelium"

        if [ "$PRIMARY_IP_TYPE" = "public" ] && [ -n "$VM_IP" ]; then
            echo "🔄 Falling back to public IPv4..."
            CONNECT_IP="$VM_IP"
            CONNECT_METHOD="public"
        else
            # Try WireGuard as fallback
            if [ -n "$VM_IP" ]; then
                echo "🔄 Falling back to WireGuard network..."
                CONNECT_IP="$VM_IP"
                CONNECT_METHOD="wireguard"

                # Attempt WireGuard connection
                WG_CONF="$STATE_DIR/wg.conf"

                # Determine interface name - use wg1 for tfgrid-compose
                WG_INTERFACE="wg1"

                # Stop existing interface (try both wg-quick down and manual removal)
                sudo wg-quick down "$WG_INTERFACE" 2>/dev/null || true
                sudo ip link delete "$WG_INTERFACE" 2>/dev/null || true

                # Start WireGuard with fresh config
                if ! sudo wg-quick up "$WG_CONF" 2>/dev/null; then
                    echo "❌ WireGuard connection also failed"
                    echo ""
                    echo "Troubleshooting:"
                    echo "  1. VM may still be booting (wait 30-60 seconds)"
                    echo "  2. Check VM status: tfgrid-compose logs tfgrid-ai-agent"
                    echo "  3. Try manual connections when VM is ready"
                    exit 1
                fi

                # Wait for connection and verify
                sleep 2

                if ! ping -c 1 -W 2 "$VM_IP" &>/dev/null; then
                    echo "❌ WireGuard fallback failed too"
                    echo ""
                    echo "Troubleshooting:"
                    echo "  1. VM may still be booting (wait 30-60 seconds)"
                    echo "  2. Check VM status: tfgrid-compose logs tfgrid-ai-agent"
                    echo "  3. Network issues in your environment"
                    exit 1
                fi

                echo "✅ WireGuard fallback successful"
            else
                echo "❌ Cannot reach VM via Mycelium and no WireGuard IP available"
                exit 1
            fi
        fi
    fi
fi

# Format IP for SSH; use raw IP (IPv4 or IPv6)
SSH_TARGET="root@$CONNECT_IP"

echo "🔌 Connecting via $CONNECT_METHOD to $CONNECT_IP..."
echo ""

# SSH into VM
ssh -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    $SSH_TARGET
