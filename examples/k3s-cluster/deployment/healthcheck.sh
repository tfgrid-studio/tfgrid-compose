#!/bin/bash
# K3s - Health check hook
set -e

echo "Checking K3s cluster health..."

# Check if k3s is running
if ! systemctl is-active --quiet k3s || ! systemctl is-active --quiet k3s-agent; then
    echo "❌ K3s service not running"
    exit 1
fi

# Check if kubectl works
if command -v kubectl &> /dev/null; then
    if kubectl get nodes &> /dev/null; then
        echo "✅ K3s cluster is healthy"
        exit 0
    fi
fi

echo "⚠️  K3s installed but cluster not fully ready"
exit 0
