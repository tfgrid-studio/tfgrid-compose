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
$TF_CMD apply -input=false tfplan 2>&1 | tee "$STATE_DIR/terraform-apply.log"
tf_apply_exit_code=${PIPESTATUS[0]}

if [ "$tf_apply_exit_code" -ne 0 ]; then
    log_error "Terraform apply failed. Check: $STATE_DIR/terraform-apply.log"
    cd "$orig_dir"
    exit 1
fi
log_info "Extracting infrastructure outputs..."

# ==============================================================================
# Capture all network IP outputs
# ==============================================================================

# Get all 4 network IPs from Terraform outputs
mycelium_ip=$($TF_CMD output -raw mycelium_ip 2>/dev/null || echo "")
wireguard_ip=$($TF_CMD output -raw wireguard_ip 2>/dev/null || echo "")
ipv4_address=$($TF_CMD output -raw ipv4_address 2>/dev/null || echo "")
ipv6_address=$($TF_CMD output -raw ipv6_address 2>/dev/null || echo "")

# Get provisioned networks list
provisioned_networks=$($TF_CMD output -raw provisioned_networks 2>/dev/null || echo "")

# Strip CIDR notation if present (e.g., 185.69.167.152/24 → 185.69.167.152)
[ -n "$mycelium_ip" ] && mycelium_ip=$(echo "$mycelium_ip" | cut -d'/' -f1)
[ -n "$wireguard_ip" ] && wireguard_ip=$(echo "$wireguard_ip" | cut -d'/' -f1)
[ -n "$ipv4_address" ] && ipv4_address=$(echo "$ipv4_address" | cut -d'/' -f1)
[ -n "$ipv6_address" ] && ipv6_address=$(echo "$ipv6_address" | cut -d'/' -f1)

# Save all available IPs to state.yaml
[ -n "$mycelium_ip" ] && echo "mycelium_address: $mycelium_ip" >> "$STATE_DIR/state.yaml"
[ -n "$wireguard_ip" ] && echo "wireguard_address: $wireguard_ip" >> "$STATE_DIR/state.yaml"
[ -n "$ipv4_address" ] && echo "ipv4_address: $ipv4_address" >> "$STATE_DIR/state.yaml"
[ -n "$ipv6_address" ] && echo "ipv6_address: $ipv6_address" >> "$STATE_DIR/state.yaml"
[ -n "$provisioned_networks" ] && echo "provisioned_networks: $provisioned_networks" >> "$STATE_DIR/state.yaml"

# Log captured IPs
[ -n "$mycelium_ip" ] && log_success "Mycelium IP: $mycelium_ip"
[ -n "$wireguard_ip" ] && log_success "WireGuard IP: $wireguard_ip"
[ -n "$ipv4_address" ] && log_success "Public IPv4: $ipv4_address"
[ -n "$ipv6_address" ] && log_success "Public IPv6: $ipv6_address"

# Validate at least one IP was captured
if [ -z "$mycelium_ip" ] && [ -z "$wireguard_ip" ] && [ -z "$ipv4_address" ] && [ -z "$ipv6_address" ]; then
    log_error "No network IPs captured from Terraform outputs!"
    cd "$orig_dir"
    exit 1
fi

# ==============================================================================
# Legacy compatibility: primary_ip and primary_ip_type
# These are deprecated but kept for backward compatibility
# ==============================================================================

primary_ip=$($TF_CMD output -raw primary_ip 2>/dev/null || echo "")
primary_ip_type=$($TF_CMD output -raw primary_ip_type 2>/dev/null || echo "")

if [ -n "$primary_ip" ]; then
    primary_ip=$(echo "$primary_ip" | cut -d'/' -f1)
    echo "primary_ip: $primary_ip" >> "$STATE_DIR/state.yaml"
    echo "primary_ip_type: $primary_ip_type" >> "$STATE_DIR/state.yaml"
fi

# ==============================================================================
# Other deployment metadata
# ==============================================================================

# Get deployment name
deployment_name=$($TF_CMD output -raw deployment_name 2>/dev/null || echo "")
if [ -n "$deployment_name" ]; then
    echo "deployment_name: $deployment_name" >> "$STATE_DIR/state.yaml"
fi

# WireGuard config (for local WireGuard interface setup)
wg_config=$($TF_CMD output -raw wg_config 2>/dev/null || echo "")
if [ -n "$wg_config" ]; then
    echo "$wg_config" > "$STATE_DIR/wg.conf"
    log_info "WireGuard config saved"
fi

# Optional: Secondary IPs (for multi-node patterns like gateway, k3s)
secondary_ips=$($TF_CMD output -json secondary_ips 2>/dev/null || echo "")
if [ -n "$secondary_ips" ] && [ "$secondary_ips" != "null" ]; then
    echo "secondary_ips: $secondary_ips" >> "$STATE_DIR/state.yaml"
fi

cd "$orig_dir"
log_success "Infrastructure created"
