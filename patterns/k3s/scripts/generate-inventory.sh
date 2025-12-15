#!/usr/bin/env bash
set -euo pipefail

# Get script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_DIR="$PROJECT_ROOT/infrastructure"
OUTPUT_FILE="$PROJECT_ROOT/platform/inventory.ini"

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

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load environment configuration
load_env_config() {
    # Load .env file if it exists
    if [ -f "$PROJECT_ROOT/.env" ]; then
        log_info "Loading configuration from .env file..."
        set -a
        source "$PROJECT_ROOT/.env"
        set +a
    else
        log_warning ".env file not found, using defaults"
        # Set default values
        MAIN_NETWORK="${MAIN_NETWORK:-wireguard}"
    fi
}

# Check dependencies
command -v jq >/dev/null 2>&1 || {
    log_error "jq required but not found. Install with:"
    echo "    sudo apt install jq || brew install jq"
    exit 1
}

command -v tofu >/dev/null 2>&1 || {
    log_error "tofu (OpenTofu) required but not found."
    exit 1
}

# Check if infrastructure is deployed
if [ ! -f "$DEPLOYMENT_DIR/terraform.tfstate" ] && [ ! -f "$DEPLOYMENT_DIR/terraform.tfstate.backup" ]; then
    log_error "No infrastructure state found"
    log_error "Run: make infrastructure"
    exit 1
fi

log_info "Generating inventory from Terraform outputs..."

# Load environment configuration
load_env_config

# Get Terraform outputs
terraform_output=$(tofu -chdir="$DEPLOYMENT_DIR" show -json)

# Extract node information
management_wireguard_ip=$(echo "$terraform_output" | jq -r '.values.outputs.management_node_wireguard_ip.value // empty')
management_mycelium_ip=$(echo "$terraform_output" | jq -r '.values.outputs.management_mycelium_ip.value // empty')
wireguard_ips=$(echo "$terraform_output" | jq -r '.values.outputs.wireguard_ips.value // {}')
mycelium_ips=$(echo "$terraform_output" | jq -r '.values.outputs.mycelium_ips.value // {}')

# Extract ingress node information (optional)
ingress_wireguard_ips=$(echo "$terraform_output" | jq -r '.values.outputs.ingress_wireguard_ips.value // {}')
ingress_mycelium_ips=$(echo "$terraform_output" | jq -r '.values.outputs.ingress_mycelium_ips.value // {}')
ingress_public_ips=$(echo "$terraform_output" | jq -r '.values.outputs.ingress_public_ips.value // {}')
has_ingress_nodes=$(echo "$terraform_output" | jq -r '.values.outputs.has_ingress_nodes.value // false')

# Choose which IPs to use for Ansible connectivity
case "${MAIN_NETWORK:-wireguard}" in
    "wireguard")
        management_ip="$management_wireguard_ip"
        node_ips="$wireguard_ips"
        log_info "Using WireGuard IPs for Ansible connectivity"
        ;;
    "mycelium")
        management_ip="$management_mycelium_ip"
        node_ips="$mycelium_ips"
        log_info "Using Mycelium IPs for Ansible connectivity"
        ;;
    *)
        log_error "Invalid MAIN_NETWORK: ${MAIN_NETWORK}. Use 'wireguard' or 'mycelium'"
        exit 1
        ;;
esac

# Validate we have the required information
if [ -z "$management_ip" ]; then
    log_error "Failed to extract management node IP from Terraform outputs"
    exit 1
fi

# Read node configuration from credentials file
CREDENTIALS_FILE="$DEPLOYMENT_DIR/credentials.auto.tfvars"
if [ ! -f "$CREDENTIALS_FILE" ]; then
    log_error "Credentials file not found: $CREDENTIALS_FILE"
    exit 1
fi

# Parse control and worker node counts from credentials
# Parse control and worker node counts by counting actual numbers
control_nodes_content=$(grep -oP 'control_nodes\s*=\s*\[\K[^\]]+' "$CREDENTIALS_FILE")
if [ -n "$control_nodes_content" ]; then
    # Remove spaces and count numbers separated by commas
    control_count=$(echo "$control_nodes_content" | tr -d ' ' | tr ',' '\n' | grep -c '^[0-9]\+$')
else
    control_count=1  # Default to 1 if parsing fails
fi

worker_nodes_content=$(grep -oP 'worker_nodes\s*=\s*\[\K[^\]]+' "$CREDENTIALS_FILE")
if [ -n "$worker_nodes_content" ]; then
    # Remove spaces and count numbers separated by commas
    worker_count=$(echo "$worker_nodes_content" | tr -d ' ' | tr ',' '\n' | grep -c '^[0-9]\+$')
else
    worker_count=2  # Default to 2 if parsing fails
fi

# Parse ingress node count (optional)
ingress_nodes_content=$(grep -oP 'ingress_nodes\s*=\s*\[\K[^\]]+' "$CREDENTIALS_FILE" 2>/dev/null || echo "")
if [ -n "$ingress_nodes_content" ] && [ "$ingress_nodes_content" != "" ]; then
    # Remove spaces and count numbers separated by commas
    ingress_count=$(echo "$ingress_nodes_content" | tr -d ' ' | tr ',' '\n' | grep -c '^[0-9]\+$' || echo 0)
else
    ingress_count=0  # Default to 0 (no dedicated ingress nodes)
fi

if [ "$ingress_count" -gt 0 ]; then
    log_info "Detected configuration: 1 management + $control_count control + $worker_count worker + $ingress_count ingress nodes"
else
    log_info "Detected configuration: 1 management + $control_count control + $worker_count worker nodes"
fi

# Clear existing file and generate new inventory
if [ "$ingress_count" -gt 0 ]; then
    config_summary="1 management + ${control_count} control + ${worker_count} worker + ${ingress_count} ingress nodes"
else
    config_summary="1 management + ${control_count} control + ${worker_count} worker nodes"
fi

cat > "$OUTPUT_FILE" << EOF
# TFGrid K3s Cluster Ansible Inventory
# Generated on $(date)
# Network: ${MAIN_NETWORK:-wireguard}
# Configuration: ${config_summary}

# Management Nodes
[k3s_management]
mgmt_host ansible_host=${management_ip} ansible_user=root ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

# K3s Control Plane Nodes
[k3s_control]
EOF

# Add control plane nodes (first N nodes from node_ips)
control_idx=0
echo "$node_ips" | jq -r 'to_entries | sort_by(.key) | .[] | select(.key | test("node_\\d+")) | .key + " " + .value' | \
while read -r key ip; do
    if [ $control_idx -lt $control_count ]; then
        node_num=$((control_idx + 1))
        echo "node${node_num} ansible_host=${ip} ansible_user=root ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'" >> "$OUTPUT_FILE"
        control_idx=$((control_idx + 1))
    fi
done

# Add worker nodes section
cat >> "$OUTPUT_FILE" << EOF

# K3s Worker Nodes
[k3s_worker]
EOF

# Add worker nodes (remaining nodes from node_ips)
worker_idx=0
echo "$node_ips" | jq -r 'to_entries | sort_by(.key) | .[] | select(.key | test("node_\\d+")) | .key + " " + .value' | \
while read -r key ip; do
    if [ $worker_idx -ge $control_count ] && [ $worker_idx -lt $((control_count + worker_count)) ]; then
        node_num=$((worker_idx + 1))
        echo "node${node_num} ansible_host=${ip} ansible_user=root ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'" >> "$OUTPUT_FILE"
    fi
    worker_idx=$((worker_idx + 1))
done

# Add ingress nodes section (if any)
if [ "$ingress_count" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << EOF

# K3s Ingress Nodes (dedicated, with public IPs)
[k3s_ingress]
EOF

    # Choose which IPs to use for ingress nodes
    case "${MAIN_NETWORK:-wireguard}" in
        "wireguard")
            ingress_node_ips="$ingress_wireguard_ips"
            ;;
        "mycelium")
            ingress_node_ips="$ingress_mycelium_ips"
            ;;
    esac

    # Add ingress nodes
    ingress_idx=0
    echo "$ingress_node_ips" | jq -r 'to_entries | sort_by(.key) | .[] | .key + " " + .value' 2>/dev/null | \
    while read -r key ip; do
        if [ -n "$ip" ]; then
            ingress_num=$((ingress_idx + 1))
            # Get public IP for this ingress node
            public_ip=$(echo "$ingress_public_ips" | jq -r ".\"$key\" // empty")
            echo "ingress${ingress_num} ansible_host=${ip} ansible_user=root public_ip=${public_ip} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'" >> "$OUTPUT_FILE"
            ingress_idx=$((ingress_idx + 1))
        fi
    done
fi

# Add cluster group
if [ "$ingress_count" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << EOF

# All K3s Nodes
[k3s_cluster:children]
k3s_management
k3s_control
k3s_worker
k3s_ingress

# Global Variables
[all:vars]
ansible_python_interpreter=/usr/bin/python3
k3s_version=v1.32.3+k3s1
primary_control_node=node1
has_ingress_nodes=true
EOF
else
    cat >> "$OUTPUT_FILE" << EOF

# All K3s Nodes
[k3s_cluster:children]
k3s_management
k3s_control
k3s_worker

# Global Variables
[all:vars]
ansible_python_interpreter=/usr/bin/python3
k3s_version=v1.32.3+k3s1
primary_control_node=node1
has_ingress_nodes=false
EOF
fi

# Extract first control plane node's IP for use as the primary control node
first_control_ip=$(echo "$node_ips" | jq -r 'to_entries | sort_by(.key) | .[0].value // empty')
if [ -n "$first_control_ip" ]; then
    echo "primary_control_ip=${first_control_ip}" >> "$OUTPUT_FILE"
fi

log_success "Ansible inventory generated: $OUTPUT_FILE"
log_info "Inventory contains:"
echo "  - 1 management node"
echo "  - ${control_count} control plane node(s)"
echo "  - ${worker_count} worker node(s)"
if [ "$ingress_count" -gt 0 ]; then
    echo "  - ${ingress_count} ingress node(s) (dedicated, with public IPs)"
fi
