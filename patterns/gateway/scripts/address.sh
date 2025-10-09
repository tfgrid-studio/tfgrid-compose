#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INFRASTRUCTURE_DIR="$SCRIPT_DIR/../infrastructure"

echo -e "${GREEN}ThreeFold Grid Gateway VM Addresses${NC}"
echo "==================================="
echo ""

cd "$INFRASTRUCTURE_DIR"

# Get all IP addresses from Terraform outputs
GATEWAY_PUBLIC_IP=$(tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||' || echo "N/A")
GATEWAY_WG_IP=$(tofu output -json gateway_wireguard_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||' || echo "N/A")
GATEWAY_MYCELIUM_IP=$(tofu output -json gateway_mycelium_ip 2>/dev/null | jq -r . 2>/dev/null || echo "N/A")
INTERNAL_WG_IPS=$(tofu output -json internal_wireguard_ips 2>/dev/null || echo "{}")
INTERNAL_MYCELIUM_IPS=$(tofu output -json internal_mycelium_ips 2>/dev/null || echo "{}")

echo -e "${YELLOW}🌐 Public Access:${NC}"
echo "  Gateway: http://$GATEWAY_PUBLIC_IP"

# Dynamically show internal VM public access URLs
echo "$INTERNAL_WG_IPS" | jq -r 'to_entries | sort_by(.key | tonumber) | .[] | "  VM \(.key):   http://'"$GATEWAY_PUBLIC_IP"':808\(.key + 1)' 2>/dev/null || true

echo ""

echo -e "${YELLOW}🔐 Private Networks (via WireGuard):${NC}"
echo "  Gateway: $GATEWAY_WG_IP"
echo "$INTERNAL_WG_IPS" | jq -r 'to_entries[] | "  VM \(.key): \(.value)"' 2>/dev/null
echo ""

echo -e "${YELLOW}🌍 Mycelium IPv6 Overlay:${NC}"
if [ "$GATEWAY_MYCELIUM_IP" != "N/A" ] && [ "$GATEWAY_MYCELIUM_IP" != "null" ]; then
    echo "  Gateway: $GATEWAY_MYCELIUM_IP"
else
    echo "  Gateway: Not assigned yet"
fi
echo "$INTERNAL_MYCELIUM_IPS" | jq -r 'to_entries[] | "  VM \(.key): \(.value)"' 2>/dev/null
echo ""

echo -e "${YELLOW}💡 Usage Tips:${NC}"
echo "  • Use 'make wireguard' to connect to private networks"
echo "  • Public websites work without WireGuard"
echo "  • SSH to private IPs requires WireGuard tunnel"