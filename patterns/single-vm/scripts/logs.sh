#!/usr/bin/env bash
# Pattern script to get application logs

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

echo "📋 Showing logs for $APP_NAME on $VM_IP..."
echo ""

# SSH and show logs
ssh -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@$VM_IP \
    "journalctl -u $APP_NAME -f"
