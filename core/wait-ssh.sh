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

if [ -z "$VM_IP" ]; then
    log_error "No VM IP found in state"
    exit 1
fi

# Strip CIDR notation if present (e.g., 185.69.167.152/24 → 185.69.167.152)
VM_IP=$(echo "$VM_IP" | cut -d'/' -f1)

log_step "Waiting for SSH to be ready..."
log_info "Network: $NETWORK_TYPE"
log_info "IP: $VM_IP"
log_info "Timeout: 300 seconds (5 minutes)"
echo ""

# Wait parameters
MAX_ATTEMPTS=30
ATTEMPT=0
SLEEP_TIME=10

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
log_error "SSH did not become ready after $MAX_ATTEMPTS attempts"
echo ""
log_info "Troubleshooting:"
echo "  1. Check VM status: tfgrid-compose status <app>"
echo "  2. Check VM address: tfgrid-compose address <app>"
echo "  3. Try manual SSH: ssh root@$VM_IP"
echo "  4. Wait longer and run this again: ./core/wait-ssh.sh"
exit 1
