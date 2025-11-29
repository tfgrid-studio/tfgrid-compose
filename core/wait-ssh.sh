#!/usr/bin/env bash
# Wait for SSH to become available on deployed VM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/network.sh"

# Use STATE_DIR from environment (absolute path)
STATE_DIR="${STATE_DIR:-.tfgrid-compose}"

if [ ! -f "$STATE_DIR/state.yaml" ]; then
    log_error "No deployment found"
    log_info "State directory not found: $STATE_DIR"
    exit 1
fi

# Get deployment ID from STATE_DIR path
# STATE_DIR path follows: /home/user/.config/tfgrid-compose/state/DEPLOYMENT_ID
DEPLOYMENT_ID=$(basename "$STATE_DIR")

# Use network-aware IP resolution that respects global preferences
VM_IP=$(get_deployment_ip "$DEPLOYMENT_ID")

# Determine network type for logging
PREFERRED_NETWORK=$(get_network_preference "$DEPLOYMENT_ID")
case "$PREFERRED_NETWORK" in
    "mycelium")
        NETWORK_TYPE="Mycelium"
        ;;
    "wireguard"|"")
        NETWORK_TYPE="WireGuard"
        ;;
    *)
        NETWORK_TYPE="Unknown"
        ;;
esac

# Also capture primary connectivity type and IP (e.g., public vs wireguard)
PRIMARY_TYPE=""
PRIMARY_IP_RAW=""
PRIMARY_IP=""
if [ -f "$STATE_DIR/state.yaml" ]; then
    PRIMARY_TYPE=$(grep "^primary_ip_type:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}' || echo "")
    PRIMARY_IP_RAW=$(grep "^primary_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}' || echo "")
    # Strip CIDR if present (e.g., 185.69.167.160/24 -> 185.69.167.160)
    if [ -n "$PRIMARY_IP_RAW" ]; then
        PRIMARY_IP=$(echo "$PRIMARY_IP_RAW" | cut -d'/' -f1)
    fi
fi

if [ -z "$VM_IP" ]; then
    log_error "No VM IP found in state"
    exit 1
fi

# Strip CIDR notation if present (e.g., 185.69.167.152/24 → 185.69.167.152)
VM_IP=$(echo "$VM_IP" | cut -d'/' -f1)

log_step "Waiting for SSH to be ready..."
log_info "Network: $NETWORK_TYPE"
log_info "IP: $VM_IP"

# Mycelium takes longer to converge, give it more time between attempts
if [ "$NETWORK_TYPE" = "Mycelium" ]; then
    MAX_ATTEMPTS=15  # 15 tries total
    SLEEP_TIME=20   # 20 seconds between attempts = ~5 minutes total
    log_info "Timeout: ~300 seconds (15 attempts × 20 seconds) - Mycelium allows longer convergence time"
else
    MAX_ATTEMPTS=30  # 30 tries total
    SLEEP_TIME=10   # 10 seconds between attempts = 5 minutes total
    log_info "Timeout: 300 seconds (30 attempts × 10 seconds)"
fi
echo ""

ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    
    # Try SSH connection
    if ssh -o ConnectTimeout=5 \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o BatchMode=yes \
           -o LogLevel=ERROR \
           root@"$VM_IP" "echo 'SSH Ready'" >/dev/null 2>&1; then
        echo ""
        log_success "SSH is ready! (attempt $ATTEMPT/$MAX_ATTEMPTS)"
        exit 0
    fi
    
    # Show progress
    echo -n "."
    
    # Wait before retry
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        sleep $SLEEP_TIME
    fi
done

echo ""

# If Mycelium was preferred but SSH never became ready, and we have a public
# primary IP, fall back to public IPv4 before giving up.
if [ "$NETWORK_TYPE" = "Mycelium" ] && [ "$PRIMARY_TYPE" = "public" ] && [ -n "$PRIMARY_IP" ] && [ "$PRIMARY_IP" != "$VM_IP" ]; then
    log_warning "SSH did not become ready over Mycelium; falling back to public IPv4 ($PRIMARY_IP)"

    VM_IP="$PRIMARY_IP"
    NETWORK_TYPE="Public IPv4"
    MAX_ATTEMPTS=10
    SLEEP_TIME=5
    ATTEMPT=0

    log_info "Network: $NETWORK_TYPE"
    log_info "IP: $VM_IP"
    echo ""

    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        ATTEMPT=$((ATTEMPT + 1))

        if ssh -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               -o BatchMode=yes \
               -o LogLevel=ERROR \
               root@"$VM_IP" "echo 'SSH Ready'" >/dev/null 2>&1; then
            echo ""
            log_success "SSH is ready over public IPv4! (attempt $ATTEMPT/$MAX_ATTEMPTS)"
            exit 0
        fi

        echo -n "."

        if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
            sleep $SLEEP_TIME
        fi
    done

    echo ""
fi

log_error "SSH did not become ready after $MAX_ATTEMPTS attempts"
echo ""
log_info "Troubleshooting:"
echo "  1. Check VM status: tfgrid-compose status <app>"
echo "  2. Check VM address: tfgrid-compose address <app>"
echo "  3. Try manual SSH: ssh root@$VM_IP"
echo "  4. Wait longer and run this again: ./core/wait-ssh.sh"
exit 1
