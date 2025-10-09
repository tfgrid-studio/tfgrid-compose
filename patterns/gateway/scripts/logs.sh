#!/usr/bin/env bash
# Show logs from gateway and backend VMs

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

echo "📋 Logs from Gateway ($GATEWAY_IP)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show Nginx logs
echo "🌐 Nginx Access Log (last 50 lines):"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    root@$GATEWAY_IP "tail -50 /var/log/nginx/access.log" 2>/dev/null || echo "No logs yet"

echo ""
echo "🌐 Nginx Error Log (last 50 lines):"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    root@$GATEWAY_IP "tail -50 /var/log/nginx/error.log" 2>/dev/null || echo "No logs yet"

# Show app logs from backend if available
echo ""
echo "📦 Application Logs (from systemd):"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    root@$GATEWAY_IP "journalctl -n 50 --no-pager" 2>/dev/null || echo "No logs available"
