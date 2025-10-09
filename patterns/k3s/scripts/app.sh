#!/bin/bash
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLATFORM_DIR="${REPO_ROOT}/platform"

# Check if platform exists by checking inventory
if [ ! -f "${PLATFORM_DIR}/inventory.ini" ]; then
  echo "⚠️ Ansible inventory not found!"
  echo "Platform must be deployed first. Run:"
  echo "  make platform"
  exit 1
fi

# Get management node IP
MGMT_HOST=$(grep "mgmt_host ansible_host" "${PLATFORM_DIR}/inventory.ini" | awk '{print $2}' | cut -d= -f2)
if [ -z "$MGMT_HOST" ]; then
  echo "Error: Could not retrieve management node IP from inventory."
  exit 1
fi

# Check if we can connect to the management node
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$MGMT_HOST "echo 'Connection successful'"; then
  echo "Error: Could not connect to management node at $MGMT_HOST"
  echo "Please ensure the platform is deployed and WireGuard is connected."
  exit 1
fi

echo "=== Deploying Applications to K3s Cluster ==="

# Currently, the app deployment is a placeholder
# TODO: Add actual application deployment code here, like Helm charts installation, etc.
ssh -o StrictHostKeyChecking=no root@$MGMT_HOST "
  # Verify cluster is accessible
  kubectl get nodes

  # Check that core components are ready
  kubectl get pods -n kube-system
  kubectl get pods -n ingress-nginx

  echo 'The K3s cluster is ready for application deployment.'
  echo 'This is a placeholder for actual app deployment.'
  echo 'You can now deploy your applications manually or extend this script.'
"

echo "=== Application Deployment Completed ==="
echo ""
echo "Your K3s cluster is ready for application deployment."
echo "To customize this process, edit scripts/app.sh with your application requirements."
echo ""
echo "To connect to the management node for manual deployment:"
echo "  make connect"
echo "  or: ssh root@$MGMT_HOST"
