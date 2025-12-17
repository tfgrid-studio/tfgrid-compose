#!/bin/bash
set -e

# K3s Ansible Retry Script
# Allows selective retry of ansible playbooks on existing infrastructure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERN_DIR="$(dirname "$SCRIPT_DIR")"
ANSIBLE_DIR="$PATTERN_DIR/platform"
INVENTORY_FILE="$ANSIBLE_DIR/inventory.ini"

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

# Function to show usage
usage() {
    echo "K3s Ansible Retry Script"
    echo ""
    echo "Usage: $0 [OPTIONS] [TAGS]"
    echo ""
    echo "OPTIONS:"
    echo "  -i, --inventory FILE    Path to ansible inventory file (default: $INVENTORY_FILE)"
    echo "  -p, --playbook FILE     Path to ansible playbook (default: $ANSIBLE_DIR/site.yml)"
    echo "  -v, --verbose           Enable verbose output"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "TAGS (selective retry):"
    echo "  control                 Retry control plane configuration only"
    echo "  worker                  Retry worker node configuration only"
    echo "  ingress                 Retry ingress node configuration only"
    echo "  common                  Retry common prerequisites only"
    echo "  management              Retry management node configuration only"
    echo "  all                     Retry all components (default)"
    echo ""
    echo "EXAMPLES:"
    echo "  $0 control              # Retry control plane only"
    echo "  $0 worker               # Retry workers only"
    echo "  $0 control worker       # Retry control and workers"
    echo "  $0 -v all               # Retry everything with verbose output"
    echo ""
    echo "STATE TRACKING:"
    echo "  The script checks for state files on the management node to determine"
    echo "  what components have already been successfully deployed."
}

# Default values
PLAYBOOK="$ANSIBLE_DIR/site.yml"
VERBOSE=""
TAGS=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--inventory)
            INVENTORY_FILE="$2"
            shift 2
            ;;
        -p|--playbook)
            PLAYBOOK="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="-v"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            # Assume it's a tag
            if [[ -z "$TAGS" ]]; then
                TAGS="--tags $1"
            else
                TAGS="$TAGS --tags $1"
            fi
            shift
            ;;
    esac
done

# Set default tags if none specified
if [[ -z "$TAGS" ]]; then
    TAGS="--tags all"
fi

# Validate files exist
if [[ ! -f "$INVENTORY_FILE" ]]; then
    log_error "Inventory file not found: $INVENTORY_FILE"
    exit 1
fi

if [[ ! -f "$PLAYBOOK" ]]; then
    log_error "Playbook file not found: $PLAYBOOK"
    exit 1
fi

# Check if ansible is available
if ! command -v ansible-playbook &> /dev/null; then
    log_error "ansible-playbook command not found. Please install Ansible."
    exit 1
fi

log_info "Starting K3s ansible retry..."
log_info "Inventory: $INVENTORY_FILE"
log_info "Playbook: $PLAYBOOK"
log_info "Tags: $TAGS"
log_info "Verbose: ${VERBOSE:-no}"

# Change to ansible directory for relative paths
cd "$ANSIBLE_DIR"

# Run ansible playbook with retry logic
log_info "Executing: ansible-playbook $VERBOSE -i $INVENTORY_FILE $TAGS $PLAYBOOK"

if ansible-playbook $VERBOSE -i "$INVENTORY_FILE" $TAGS "$PLAYBOOK"; then
    log_success "Ansible playbook completed successfully!"
    echo ""
    echo "=========================================="
    echo "🎉 RETRY COMPLETED SUCCESSFULLY"
    echo "=========================================="
    echo ""
    echo "Next steps:"
    echo "  1. Run health checks: ./scripts/healthcheck.sh"
    echo "  2. If issues persist, check logs and retry specific components"
    echo "  3. For full redeployment, use: tfgrid-compose up <project>"
    echo ""
else
    log_error "Ansible playbook failed!"
    echo ""
    echo "=========================================="
    echo "❌ RETRY FAILED"
    echo "=========================================="
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check ansible logs above for specific errors"
    echo "  2. SSH to management node and check state files:"
    echo "     ls -la /var/lib/tfgrid-compose/state/"
    echo "  3. Retry specific failing components:"
    echo "     $0 control    # Retry control plane"
    echo "     $0 worker     # Retry worker nodes"
    echo "  4. Check cluster status: kubectl get nodes"
    echo ""
    exit 1
fi
