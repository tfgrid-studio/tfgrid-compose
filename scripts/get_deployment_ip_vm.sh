#!/usr/bin/env bash
# Helper: resolve deployment IP inside VM based on network preference

set -e

STATE_FILE="${1:-/tmp/app-deployment/state.yaml}"

if [ ! -f "$STATE_FILE" ]; then
  echo "" >&2
  exit 1
fi

# Read fields with minimal dependencies (no yq inside VM by default)
get_field() {
  local key="$1"
  grep "^$key:" "$STATE_FILE" 2>/dev/null | awk '{print $2}' || echo ""
}

PREF="${DEPLOYMENT_NETWORK_PREFERENCE:-}"
VM_IP=$(get_field "ipv4_address")
PRIMARY_IP=$(get_field "primary_ip")
MYCELIUM_IP=$(get_field "mycelium_address")

# Default preference if not provided
if [ -z "$PREF" ]; then
  # Fall back to primary_ip_type when available
  PREF_TYPE=$(get_field "primary_ip_type")
  if [ "$PREF_TYPE" = "mycelium" ]; then
    PREF="mycelium"
  else
    PREF="wireguard"
  fi
fi

case "$PREF" in
  mycelium)
    if [ -n "$MYCELIUM_IP" ]; then
      echo "$MYCELIUM_IP"
      exit 0
    fi
    ;;
  wireguard|*)
    # For now both wireguard and default use primary_ip/ipv4_address
    :
    ;;
esac

# Fallback order: primary_ip, then ipv4_address
if [ -n "$PRIMARY_IP" ]; then
  echo "$PRIMARY_IP"
  exit 0
fi

if [ -n "$VM_IP" ]; then
  echo "$VM_IP"
  exit 0
fi

# Nothing usable
echo "" >&2
exit 1
