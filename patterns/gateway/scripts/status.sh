#!/usr/bin/env bash
# Check status of gateway and backend VMs

set -e

# Get IPs from state
STATE_DIR=".tfgrid-compose"

if [ ! -f "$STATE_DIR/state.yaml" ]; then
    echo "❌ No deployment found"
    exit 1
fi

GATEWAY_IP=$(grep "^gateway_ip:" "$STATE_DIR/state.yaml" | awk '{print $2}')

if [ -z "$GATEWAY_IP" ]; then
    echo "❌ No gateway IP found in state"
    exit 1
fi

echo "🌐 Gateway Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check Nginx status
echo "🔍 Nginx Status:"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    root@$GATEWAY_IP "systemctl status nginx --no-pager -l" 2>/dev/null || echo "❌ Nginx not running"

echo ""
echo "🔍 Nginx Configuration Test:"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    root@$GATEWAY_IP "nginx -t" 2>&1 || echo "❌ Nginx config has errors"

echo ""
echo "🔗 Active Connections:"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    root@$GATEWAY_IP "ss -tulpn | grep nginx" 2>/dev/null || echo "No connections"
