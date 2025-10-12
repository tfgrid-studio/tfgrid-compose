#!/bin/bash
# K3s - Configure hook (placeholder)
set -e

echo "K3s cluster configuration handled by pattern"
echo "Deploying custom Kubernetes manifests..."

# Deploy custom manifests if any
if [ -d ../manifests ]; then
    echo "Found manifests directory - will deploy after cluster is ready"
fi

echo "✅ Configuration complete!"
