#!/usr/bin/env bash
# Task: Setup WireGuard connection (simplified to match working external)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# Get state directory from environment
STATE_DIR="${STATE_DIR:-.tfgrid-compose}"

# Get app name from state file and sanitize it (remove any whitespace/newlines)
APP_NAME=$(grep "^app_name:" "$STATE_DIR/state.yaml" 2>/dev/null | sed 's/^app_name: //' | tr -d '[:space:]')
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
    log_error "WireGuard not installed. Install with: sudo apt install wireguard"
    exit 1
fi

log_info "Extracting WireGuard configuration..."

# Detect OpenTofu or Terraform (prefer OpenTofu as it's open source)
if command -v tofu &> /dev/null; then
    TF_CMD="tofu"
elif command -v terraform &> /dev/null; then
    TF_CMD="terraform"
else
    log_error "Neither OpenTofu nor Terraform found"
    exit 1
fi

# Simple interface naming (find next available wg interface number)
next_num=$(ls /sys/class/net/ | grep "^wg[0-9]" | wc -l)
wg_interface="wg$next_num"

# Use absolute path for config file
abs_state_dir="$(cd "$STATE_DIR" && pwd)"
wg_conf_file="$abs_state_dir/${wg_interface}.conf"

# Extract WireGuard config from Terraform directory
cd "$STATE_DIR/terraform" || exit 1

# Extract config using show -json (like working tfgrid-ai-agent)
TF_OUTPUT=$($TF_CMD show -json)
echo "$TF_OUTPUT" | jq -r '.values.outputs.wg_config.value' > "$wg_conf_file"

cd - >/dev/null

# Verify config was extracted
if [ ! -s "$wg_conf_file" ]; then
    log_error "WireGuard config is empty or missing"
    exit 1
fi

chmod 600 "$wg_conf_file"

# Deploy config to system
log_info "Configuring WireGuard interface: $wg_interface"
sudo cp "$wg_conf_file" "/etc/wireguard/${wg_interface}.conf"
sudo chmod 600 "/etc/wireguard/${wg_interface}.conf"

# Clean up any conflicting WireGuard interfaces
log_info "Checking for conflicting WireGuard interfaces..."

# Get the IP range from our config
our_ip_range=$(grep "AllowedIPs" "$wg_conf_file" | head -1 | awk '{print $3}' | cut -d',' -f1)

if [ -n "$our_ip_range" ]; then
    # Check for active WireGuard interfaces
    active_interfaces=$(sudo wg show interfaces 2>/dev/null || echo "")
    
    if [ -n "$active_interfaces" ]; then
        for iface in $active_interfaces; do
            # Check if this interface uses our IP range
            if sudo wg show "$iface" allowed-ips 2>/dev/null | grep -q "$our_ip_range"; then
                if [ "$iface" != "$wg_interface" ]; then
                    log_warning "Found conflicting WireGuard interface: $iface (uses same IP range)"
                    log_info "Stopping conflicting interface: $iface"
                    sudo wg-quick down "$iface" 2>/dev/null || true
                fi
            fi
        done
    fi
fi

# Clean up THIS app's previous interface if it exists
if [ -f "$STATE_DIR/wg_interface" ]; then
    OLD_INTERFACE=$(cat "$STATE_DIR/wg_interface")
    log_info "Cleaning up previous interface: $OLD_INTERFACE"
    
    # Stop the old interface
    sudo wg-quick down "$OLD_INTERFACE" 2>/dev/null || true
    
    # Remove the interface
    sudo ip link del "$OLD_INTERFACE" 2>/dev/null || true
    
    # Clean up routes from old interface
    sudo ip route del 100.64.0.0/16 dev "$OLD_INTERFACE" 2>/dev/null || true
    sudo ip route del 10.1.0.0/16 dev "$OLD_INTERFACE" 2>/dev/null || true
fi

# Start WireGuard (simple, like external)
log_info "Starting WireGuard interface..."
if ! sudo wg-quick up "$wg_interface"; then
    log_error "Failed to start WireGuard interface"
    log_info "Check config: /etc/wireguard/${wg_interface}.conf"
    exit 1
fi

# Save interface name to state for future cleanup
echo "$wg_interface" > "$STATE_DIR/wg_interface"

log_success "WireGuard connection established: $wg_interface"

# Give the network a moment to stabilize
sleep 2
