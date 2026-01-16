#!/usr/bin/env bash
# Wait for SSH to become available on deployed VM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/network.sh"

# Use STATE_DIR from environment (absolute path)
STATE_DIR="${STATE_DIR:-.tfgrid-compose}"

if [ ! -f "$STATE_DIR/state.yaml" ]; then
    log_error "No deployment found"
    log_info "State directory not found: $STATE_DIR"
    exit 1
fi

# Get deployment ID from STATE_DIR path
# STATE_DIR path follows: /home/user/.config/tfgrid-compose/state/DEPLOYMENT_ID
DEPLOYMENT_ID=$(basename "$STATE_DIR")

# Use network-aware IP resolution that respects global preferences
VM_IP=$(get_deployment_ip "$DEPLOYMENT_ID")

# Determine network type for logging
PREFERRED_NETWORK=$(get_network_preference "$DEPLOYMENT_ID")
case "$PREFERRED_NETWORK" in
    "mycelium")
        NETWORK_TYPE="Mycelium"
        ;;
    "wireguard"|"")
        NETWORK_TYPE="WireGuard"
        ;;
    *)
        NETWORK_TYPE="Unknown"
        ;;
esac

# Also capture primary connectivity type and IP (e.g., public vs wireguard)
PRIMARY_TYPE=""
PRIMARY_IP_RAW=""
PRIMARY_IP=""
if [ -f "$STATE_DIR/state.yaml" ]; then
    PRIMARY_TYPE=$(grep "^primary_ip_type:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}' || echo "")
    PRIMARY_IP_RAW=$(grep "^primary_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}' || echo "")
    # Strip CIDR if present (e.g., 185.69.167.160/24 -> 185.69.167.160)
    if [ -n "$PRIMARY_IP_RAW" ]; then
        PRIMARY_IP=$(echo "$PRIMARY_IP_RAW" | cut -d'/' -f1)
    fi
fi

if [ -z "$VM_IP" ]; then
    log_error "No VM IP found in state"
    exit 1
fi

# Strip CIDR notation if present (e.g., 185.69.167.152/24 → 185.69.167.152)
VM_IP=$(echo "$VM_IP" | cut -d'/' -f1)

log_step "Waiting for SSH to be ready..."
log_info "Network: $NETWORK_TYPE"
log_info "IP: $VM_IP"

# Configurable timeouts via environment variables
# Mycelium takes longer to converge, give it more time between attempts
if [ "$NETWORK_TYPE" = "Mycelium" ]; then
    # Configurable via MYCELIUM_SSH_MAX_ATTEMPTS and MYCELIUM_SSH_SLEEP
    # Default: 25 attempts × 20 seconds = ~8-9 minutes total (increased from 15 × 20 = 5 min)
    MAX_ATTEMPTS=${MYCELIUM_SSH_MAX_ATTEMPTS:-25}
    SLEEP_TIME=${MYCELIUM_SSH_SLEEP:-20}
    TOTAL_TIMEOUT=$((MAX_ATTEMPTS * SLEEP_TIME))
    log_info "Timeout: ~${TOTAL_TIMEOUT} seconds ($MAX_ATTEMPTS attempts × $SLEEP_TIME seconds) - Mycelium allows longer convergence time"
else
    # Configurable via SSH_MAX_ATTEMPTS and SSH_SLEEP
    MAX_ATTEMPTS=${SSH_MAX_ATTEMPTS:-30}
    SLEEP_TIME=${SSH_SLEEP:-10}
    TOTAL_TIMEOUT=$((MAX_ATTEMPTS * SLEEP_TIME))
    log_info "Timeout: ${TOTAL_TIMEOUT} seconds ($MAX_ATTEMPTS attempts × $SLEEP_TIME seconds)"
fi
echo ""

ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    # Try SSH connection
    if ssh -o ConnectTimeout=5 \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o BatchMode=yes \
           -o LogLevel=ERROR \
           root@"$VM_IP" "echo 'SSH Ready'" >/dev/null 2>&1; then
        echo ""
        log_success "SSH is ready! (attempt $ATTEMPT/$MAX_ATTEMPTS)"
        exit 0
    fi

    # Show progress
    echo -n "."

    # Wait before retry
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        sleep $SLEEP_TIME
    fi
done

echo ""

# === Mycelium Restart Fallback ===
# If Mycelium was preferred but SSH never became ready, try restarting local Mycelium
# daemon to re-establish connectivity, then retry with additional attempts.
if [ "$NETWORK_TYPE" = "Mycelium" ]; then
    # Check if local mycelium daemon is running and can be restarted
    MYCELIUM_RESTARTED=false
    if command -v systemctl &>/dev/null; then
        if systemctl is-active --quiet mycelium 2>/dev/null; then
            # Only attempt restart if we have passwordless sudo (won't prompt)
            if sudo -n true 2>/dev/null; then
                log_warning "SSH not ready after initial attempts. Restarting local Mycelium..."

                if sudo -n systemctl restart mycelium 2>/dev/null; then
                    MYCELIUM_RESTARTED=true
                    log_info "Mycelium daemon restarted. Waiting for reconnection..."
                    sleep 15  # Give mycelium time to reconnect to the mesh
                else
                    log_warning "Could not restart Mycelium daemon"
                fi
            else
                log_info "Passwordless sudo not available, skipping Mycelium restart"
                log_info "You can manually run: sudo systemctl restart mycelium"
            fi
        else
            log_info "Mycelium daemon not running via systemd, skipping restart attempt"
        fi
    fi

    # If we restarted mycelium, do additional retry attempts
    if [ "$MYCELIUM_RESTARTED" = "true" ]; then
        # Second wave: fewer attempts after restart
        RETRY_ATTEMPTS=${MYCELIUM_SSH_RETRY_ATTEMPTS:-15}
        RETRY_SLEEP=${MYCELIUM_SSH_RETRY_SLEEP:-15}
        ATTEMPT=0

        log_info "Retrying SSH after Mycelium restart ($RETRY_ATTEMPTS attempts × $RETRY_SLEEP seconds)..."
        echo ""

        while [ $ATTEMPT -lt $RETRY_ATTEMPTS ]; do
            ATTEMPT=$((ATTEMPT + 1))

            if ssh -o ConnectTimeout=5 \
                   -o StrictHostKeyChecking=no \
                   -o UserKnownHostsFile=/dev/null \
                   -o BatchMode=yes \
                   -o LogLevel=ERROR \
                   root@"$VM_IP" "echo 'SSH Ready'" >/dev/null 2>&1; then
                echo ""
                log_success "SSH is ready after Mycelium restart! (retry attempt $ATTEMPT/$RETRY_ATTEMPTS)"
                exit 0
            fi

            echo -n "."

            if [ $ATTEMPT -lt $RETRY_ATTEMPTS ]; then
                sleep $RETRY_SLEEP
            fi
        done

        echo ""
    fi
fi

# === Public IPv4 Fallback ===
# If Mycelium was preferred but SSH never became ready, and we have a public
# primary IP, fall back to public IPv4 before giving up.
if [ "$NETWORK_TYPE" = "Mycelium" ] && [ "$PRIMARY_TYPE" = "public" ] && [ -n "$PRIMARY_IP" ] && [ "$PRIMARY_IP" != "$VM_IP" ]; then
    log_warning "SSH did not become ready over Mycelium; falling back to public IPv4 ($PRIMARY_IP)"

    VM_IP="$PRIMARY_IP"
    NETWORK_TYPE="Public IPv4"
    MAX_ATTEMPTS=${IPV4_FALLBACK_MAX_ATTEMPTS:-10}
    SLEEP_TIME=${IPV4_FALLBACK_SLEEP:-5}
    ATTEMPT=0

    log_info "Network: $NETWORK_TYPE"
    log_info "IP: $VM_IP"
    echo ""

    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        ATTEMPT=$((ATTEMPT + 1))

        if ssh -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               -o BatchMode=yes \
               -o LogLevel=ERROR \
               root@"$VM_IP" "echo 'SSH Ready'" >/dev/null 2>&1; then
            echo ""
            log_success "SSH is ready over public IPv4! (attempt $ATTEMPT/$MAX_ATTEMPTS)"
            exit 0
        fi

        echo -n "."

        if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
            sleep $SLEEP_TIME
        fi
    done

    echo ""
fi

log_error "SSH did not become ready after all attempts"
echo ""
log_info "Troubleshooting:"
echo "  1. Check VM status: tfgrid-compose status <app>"
echo "  2. Check VM address: tfgrid-compose address <app>"
echo "  3. Try manual SSH: ssh root@$VM_IP"
echo "  4. Wait and resume: tfgrid-compose up <app> --resume"
echo "  5. Check local Mycelium: systemctl status mycelium"
exit 1
