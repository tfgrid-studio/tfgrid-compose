#!/usr/bin/env bash
# Show logs from K3s cluster

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

echo "☸️  K3s Cluster Logs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Show K3s service logs
echo "🔍 K3s Service Log (last 50 lines):"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    root@$MASTER_IP "journalctl -u k3s -n 50 --no-pager" 2>/dev/null || echo "No logs yet"

echo ""
echo "📦 Recent Pod Events:"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    root@$MASTER_IP "kubectl get events --sort-by=.metadata.creationTimestamp | tail -20" 2>/dev/null || echo "No events"
