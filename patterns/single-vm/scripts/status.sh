#!/usr/bin/env bash
# Pattern script to check application status

set -e

# Get state directory (use global state if not set)
STATE_DIR="${STATE_DIR:-$STATE_BASE_DIR/$APP_NAME}"

# Read deployment info
if [ ! -f "$STATE_DIR/state.yaml" ]; then
    echo "❌ No deployment found. Run 'tfgrid-compose up' first."
    exit 1
fi

# Get VM IP and app name from state
VM_IP=$(grep "ipv4_address:" "$STATE_DIR/state.yaml" | awk '{print $2}')
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
    "systemctl status tfgrid-ai-agent || echo 'Service not found, checking if AI agent is running manually...'; ps aux | grep -v grep | grep -E '(ai-agent|qwen|agent-loop)' || echo 'No AI agent processes found'"
