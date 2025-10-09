#!/usr/bin/env bash
# Pattern script to SSH into VM

set -e

# Get state directory
STATE_DIR=".tfgrid-compose"

# Read deployment info
if [ ! -f "$STATE_DIR/state.yaml" ]; then
    echo "❌ No deployment found. Run 'tfgrid-compose up' first."
    exit 1
fi

# Get VM IP from state
VM_IP=$(grep "vm_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}')

if [ -z "$VM_IP" ]; then
    echo "❌ Could not read VM IP from state"
    exit 1
fi

echo "🔌 Connecting to $VM_IP..."
echo ""

# SSH into VM
ssh -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@$VM_IP
