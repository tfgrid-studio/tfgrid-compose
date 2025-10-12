#!/usr/bin/env bash
# Wait for SSH to become available on deployed VM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

STATE_DIR=".tfgrid-compose"

if [ ! -f "$STATE_DIR/state.yaml" ]; then
    log_error "No deployment found"
    log_info "State directory not found: $STATE_DIR"
    exit 1
fi

# Get VM IP from state
VM_IP=$(grep "^vm_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}')

if [ -z "$VM_IP" ]; then
    log_error "No VM IP found in state"
    exit 1
fi

# Strip CIDR notation if present (e.g., 185.69.167.152/24 → 185.69.167.152)
VM_IP=$(echo "$VM_IP" | cut -d'/' -f1)

log_step "Waiting for SSH to be ready on $VM_IP..."
log_info "This may take a few minutes (timeout: 300 seconds)..."
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
