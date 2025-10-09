#!/usr/bin/env bash
# Pattern script to check application status

set -e

# Get state directory
STATE_DIR=".tfgrid-compose"

# Read deployment info
if [ ! -f "$STATE_DIR/state.yaml" ]; then
    echo "❌ No deployment found. Run 'tfgrid-compose up' first."
    exit 1
fi

# Get VM IP and app name from state
VM_IP=$(grep "vm_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}')
APP_NAME=$(grep "app_name:" "$STATE_DIR/state.yaml" | awk '{print $2}')

if [ -z "$VM_IP" ] || [ -z "$APP_NAME" ]; then
    echo "❌ Could not read deployment state"
    exit 1
fi

echo "🔍 Checking status of $APP_NAME on $VM_IP..."
echo ""

# SSH and check status
ssh -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@$VM_IP \
    "systemctl status $APP_NAME"
