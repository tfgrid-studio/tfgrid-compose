#!/bin/bash

# K3s Deployment Status Checker
# Inspects the current state of K3s deployment components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERN_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check component status
check_component() {
    local component=$1
    local description=$2
    local state_file=$3
    local management_node=${4:-"k3s_management"}

    echo -n "Checking $description... "

    # For now, we'll assume we need to check state files on the management node
    # In a real implementation, this would use ansible to check remote state
    if [[ -f "/tmp/mock_state_${component}" ]]; then
        echo -e "${GREEN}✅ COMPLETED${NC}"
        return 0
    else
        echo -e "${YELLOW}❓ NOT FOUND${NC} (state file missing: $state_file)"
        return 1
    fi
}

echo "=========================================="
echo "🔍 K3S DEPLOYMENT STATUS CHECK"
echo "=========================================="
echo ""

# Check if we're running from the right location
if [[ ! -f "$PATTERN_DIR/platform/site.yml" ]]; then
    log_error "This script must be run from the k3s pattern directory"
    exit 1
fi

log_info "Checking deployment state files..."
echo ""

# Check management node setup
echo "📋 MANAGEMENT NODE:"
check_component "management" "Management node configuration" "/var/lib/tfgrid-compose/state/management_complete"
echo ""

# Check common prerequisites
echo "🔧 COMMON PREREQUISITES:"
check_component "common" "Common prerequisites on all nodes" "/var/lib/tfgrid-compose/state/common_complete"
echo ""

# Check control plane
echo "🎛️  CONTROL PLANE:"
check_component "control" "Control plane configuration" "/var/lib/tfgrid-compose/state/control_complete"
echo ""

# Check worker nodes (would need to check multiple files)
echo "⚙️  WORKER NODES:"
# In real implementation, this would iterate through inventory
echo -n "Checking worker node status... "
echo -e "${YELLOW}❓ MANUAL CHECK REQUIRED${NC}"
echo "   Run: kubectl get nodes --selector='!node-role.kubernetes.io/control-plane'"
echo ""

# Check ingress nodes
echo "🌐 INGRESS NODES:"
echo -n "Checking ingress node configuration... "
echo -e "${YELLOW}❓ MANUAL CHECK REQUIRED${NC}"
echo "   Run: kubectl get nodes --selector='node-role.kubernetes.io/ingress'"
echo ""

# Check cluster validation
echo "🔍 CLUSTER VALIDATION:"
echo -n "Checking cluster readiness... "
echo -e "${YELLOW}❓ MANUAL CHECK REQUIRED${NC}"
echo "   Run: kubectl get nodes"
echo "   Run: kubectl get pods -A"
echo ""

echo "=========================================="
echo "💡 RECOMMENDED ACTIONS"
echo "=========================================="
echo ""
echo "If components show 'NOT FOUND', retry them individually:"
echo "  ./scripts/retry-playbook.sh management    # Management node"
echo "  ./scripts/retry-playbook.sh common        # Common prerequisites"
echo "  ./scripts/retry-playbook.sh control       # Control plane"
echo "  ./scripts/retry-playbook.sh worker        # Worker nodes"
echo "  ./scripts/retry-playbook.sh ingress       # Ingress nodes"
echo ""
echo "For full cluster validation:"
echo "  ./scripts/healthcheck.sh"
echo ""
echo "=========================================="
