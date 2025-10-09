#!/usr/bin/env bash
# SSH into K3s master node

set -e

# Get master IP from state
STATE_DIR=".tfgrid-compose"

if [ ! -f "$STATE_DIR/state.yaml" ]; then
    echo "❌ No deployment found"
    exit 1
fi

MASTER_IP=$(grep "^master_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}')

if [ -z "$MASTER_IP" ]; then
    echo "❌ No master IP found in state"
    exit 1
fi

echo "🔗 Connecting to K3s master: $MASTER_IP"
echo ""

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@$MASTER_IP
