#!/usr/bin/env bash
# Task: Run Terraform deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Get state directory from environment or use default
STATE_DIR="${STATE_DIR:-.tfgrid-compose}"

log_step "Running Terraform..."

# Save current directory for log paths
orig_dir="$(pwd)"

cd "$STATE_DIR/terraform" || exit 1

# Initialize Terraform
log_info "Initializing Terraform..."
echo ""
if ! terraform init -input=false 2>&1 | tee "$orig_dir/$STATE_DIR/terraform-init.log"; then
    log_error "Terraform init failed. Check: $STATE_DIR/terraform-init.log"
    cd "$orig_dir"
    exit 1
fi

# Plan
echo ""
log_info "Planning infrastructure..."
echo ""
if ! terraform plan -out=tfplan 2>&1 | tee "$orig_dir/$STATE_DIR/terraform-plan.log"; then
    log_error "Terraform plan failed. Check: $STATE_DIR/terraform-plan.log"
    cd "$orig_dir"
    exit 1
fi

# Apply
echo ""
log_info "Applying infrastructure changes..."
echo ""
if ! terraform apply -auto-approve tfplan 2>&1 | tee "$orig_dir/$STATE_DIR/terraform-apply.log"; then
    log_error "Terraform apply failed. Check: $STATE_DIR/terraform-apply.log"
    cd "$orig_dir"
    exit 1
fi

# Get outputs using STANDARD pattern contract
log_info "Extracting infrastructure outputs..."

# Get primary IP (REQUIRED by all patterns)
primary_ip=$(terraform output -raw primary_ip 2>/dev/null || echo "")
primary_ip_type=$(terraform output -raw primary_ip_type 2>/dev/null || echo "unknown")

if [ -n "$primary_ip" ]; then
    echo "vm_ip: $primary_ip" >> "$orig_dir/$STATE_DIR/state.yaml"
    echo "primary_ip: $primary_ip" >> "$orig_dir/$STATE_DIR/state.yaml"
    echo "primary_ip_type: $primary_ip_type" >> "$orig_dir/$STATE_DIR/state.yaml"
    log_success "Primary IP ($primary_ip_type): $primary_ip"
else
    log_error "No primary_ip output from pattern!"
    cd "$orig_dir"
    exit 1
fi

# Get deployment name
deployment_name=$(terraform output -raw deployment_name 2>/dev/null || echo "")
if [ -n "$deployment_name" ]; then
    echo "deployment_name: $deployment_name" >> "$orig_dir/$STATE_DIR/state.yaml"
fi

# Get node IDs (as JSON array)
node_ids=$(terraform output -json node_ids 2>/dev/null || echo "[]")
echo "node_ids: $node_ids" >> "$orig_dir/$STATE_DIR/state.yaml"

# Optional: Mycelium IP
mycelium_ip=$(terraform output -raw mycelium_ip 2>/dev/null || echo "")
if [ -n "$mycelium_ip" ]; then
    echo "mycelium_ip: $mycelium_ip" >> "$orig_dir/$STATE_DIR/state.yaml"
    log_info "Mycelium IP: $mycelium_ip"
fi

# Optional: Secondary IPs (for multi-node patterns like gateway, k3s)
secondary_ips=$(terraform output -json secondary_ips 2>/dev/null || echo "")
if [ -n "$secondary_ips" ] && [ "$secondary_ips" != "null" ]; then
    echo "secondary_ips: $secondary_ips" >> "$orig_dir/$STATE_DIR/state.yaml"
fi

cd "$orig_dir"
log_success "Infrastructure created"
