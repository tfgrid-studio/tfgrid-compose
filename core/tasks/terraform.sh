#!/usr/bin/env bash
# Task: Run Terraform/OpenTofu deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Get state directory from environment or use default
STATE_DIR="${STATE_DIR:-.tfgrid-compose}"

log_step "Running Terraform..."

# Detect OpenTofu or Terraform (prefer OpenTofu as it's open source)
if command -v tofu &> /dev/null; then
    TF_CMD="tofu"
elif command -v terraform &> /dev/null; then
    TF_CMD="terraform"
else
    log_error "Neither OpenTofu nor Terraform found"
    exit 1
fi

# Save current directory for log paths
orig_dir="$(pwd)"
cd "$STATE_DIR/terraform" || exit 1

# Initialize
log_info "Initializing Terraform..."
echo ""
if ! $TF_CMD init -input=false 2>&1 | tee "$STATE_DIR/terraform-init.log"; then
    log_error "Terraform init failed. Check: $STATE_DIR/terraform-init.log"
    cd "$orig_dir"
    exit 1
fi

# Plan
echo ""
log_info "Planning infrastructure..."
echo ""
if ! $TF_CMD plan -out=tfplan -input=false 2>&1 | tee "$STATE_DIR/terraform-plan.log"; then
    log_error "Terraform plan failed. Check: $STATE_DIR/terraform-plan.log"
    cd "$orig_dir"
    exit 1
fi

# Apply
echo ""
log_info "Applying infrastructure changes..."
echo ""
if ! $TF_CMD apply -input=false tfplan 2>&1 | tee "$STATE_DIR/terraform-apply.log"; then
    log_error "Terraform apply failed. Check: $STATE_DIR/terraform-apply.log"
    cd "$orig_dir"
    exit 1
fi
log_info "Extracting infrastructure outputs..."

# Get primary IP and type (REQUIRED by all patterns)
primary_ip=$($TF_CMD output -raw primary_ip 2>/dev/null || echo "")
primary_ip_type=$($TF_CMD output -raw primary_ip_type 2>/dev/null || echo "wireguard")

if [ -n "$primary_ip" ]; then
    # Strip CIDR notation if present (e.g., 185.69.167.152/24 → 185.69.167.152)
    primary_ip=$(echo "$primary_ip" | cut -d'/' -f1)
    
    # STATE_DIR is already absolute path, don't prepend $orig_dir
    echo "vm_ip: $primary_ip" >> "$STATE_DIR/state.yaml"
    echo "primary_ip: $primary_ip" >> "$STATE_DIR/state.yaml"
    echo "primary_ip_type: $primary_ip_type" >> "$STATE_DIR/state.yaml"
    log_success "Primary IP ($primary_ip_type): $primary_ip"
else
    log_error "No primary_ip output from pattern!"
    cd "$orig_dir"
    exit 1
fi

# Get deployment name
deployment_name=$($TF_CMD output -raw deployment_name 2>/dev/null || echo "")
if [ -n "$deployment_name" ]; then
    echo "deployment_name: $deployment_name" >> "$STATE_DIR/state.yaml"
fi

# Pattern-specific outputs
mycelium_ip=$($TF_CMD output -raw mycelium_ip 2>/dev/null || echo "")
if [ -n "$mycelium_ip" ]; then
    echo "mycelium_ip: $mycelium_ip" >> "$STATE_DIR/state.yaml"
    log_info "Mycelium IP: $mycelium_ip"
fi

wg_config=$($TF_CMD output -raw wg_config 2>/dev/null || echo "")
if [ -n "$wg_config" ]; then
    echo "$wg_config" > "$STATE_DIR/wg.conf"
    log_info "WireGuard config saved to: $STATE_DIR/wg.conf"
fi

# Optional: Secondary IPs (for multi-node patterns like gateway, k3s)
secondary_ips=$($TF_CMD output -json secondary_ips 2>/dev/null || echo "")
if [ -n "$secondary_ips" ] && [ "$secondary_ips" != "null" ]; then
    echo "secondary_ips: $secondary_ips" >> "$STATE_DIR/state.yaml"
fi

cd "$orig_dir"
log_success "Infrastructure created"
