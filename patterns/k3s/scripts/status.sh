#!/usr/bin/env bash
# Check status of K3s cluster

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

echo "☸️  K3s Cluster Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check K3s service
echo "🔍 K3s Service:"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    root@$MASTER_IP "systemctl status k3s --no-pager | head -20" 2>/dev/null || echo "❌ K3s not running"

echo ""
echo "🖥️  Cluster Nodes:"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    root@$MASTER_IP "kubectl get nodes" 2>/dev/null || echo "No nodes"

echo ""
echo "📦 Running Pods:"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    root@$MASTER_IP "kubectl get pods --all-namespaces" 2>/dev/null || echo "No pods"

echo ""
echo "🌐 Services:"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
    root@$MASTER_IP "kubectl get svc --all-namespaces" 2>/dev/null || echo "No services"
