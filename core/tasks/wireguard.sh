#!/usr/bin/env bash
# Task: Setup WireGuard connection

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Get state directory from environment
STATE_DIR="${STATE_DIR:-.tfgrid-compose}"

# Get app name from state file (source of truth)
APP_NAME=$(grep "^app_name:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')
if [ -z "$APP_NAME" ]; then
    log_error "No app_name found in state file"
    exit 1
fi

# Check if we need WireGuard
primary_ip_type=$(grep "^primary_ip_type:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}' || echo "unknown")

if [ "$primary_ip_type" != "wireguard" ]; then
    log_info "Connectivity type: $primary_ip_type (WireGuard not needed)"
    exit 0
fi

log_step "Setting up WireGuard connection..."

# Check if WireGuard is installed
if ! command -v wg-quick &> /dev/null; then
    log_warning "WireGuard not installed. Install it to enable connectivity:"
    log_info "  Ubuntu/Debian: sudo apt install wireguard"
    log_info "  macOS: brew install wireguard-tools"
    log_error "WireGuard setup failed"
    exit 1
fi

# Extract WireGuard config from Terraform
cd "$STATE_DIR/terraform" || exit 1

wg_config=$(terraform output -raw wg_config 2>/dev/null)

if [ -z "$wg_config" ] || [ "$wg_config" == "null" ]; then
    log_error "No WireGuard config found in Terraform outputs"
    exit 1
fi

cd - >/dev/null

# Strip 'tfgrid-' prefix if present to match original naming (e.g., wg-ai-agent not wg-tfgrid-ai-agent)
INTERFACE_NAME="${APP_NAME#tfgrid-}"

# Use app-specific interface name
wg_interface="wg-${INTERFACE_NAME}"
wg_conf_file="$STATE_DIR/${wg_interface}.conf"

# Save config to file
echo "$wg_config" > "$wg_conf_file"
chmod 600 "$wg_conf_file"

# Deploy config to system
log_info "Configuring WireGuard interface: $wg_interface"

# Stop existing interface if it exists (clean shutdown)
sudo wg-quick down "$wg_interface" 2>/dev/null || true

# Copy config to system location
sudo cp "$wg_conf_file" "/etc/wireguard/${wg_interface}.conf"
sudo chmod 600 "/etc/wireguard/${wg_interface}.conf"

# Start WireGuard
log_info "Starting WireGuard interface..."
if ! sudo wg-quick up "$wg_interface" 2>&1 | tee -a "$STATE_DIR/wireguard.log"; then
    log_error "Failed to start WireGuard"
    exit 1
fi

log_success "WireGuard connection established: $wg_interface"

# Give the network a moment to stabilize
sleep 2
