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

# Get gateway IP from Terraform outputs
GATEWAY_IP=$(cd "$INFRASTRUCTURE_DIR" && tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||' || echo "")

if [ -z "$GATEWAY_IP" ] || [ "$GATEWAY_IP" = "null" ]; then
    echo -e "${RED}Gateway IP not found. Have you deployed infrastructure yet?${NC}"
    echo "Run 'make infrastructure' first."
    exit 1
fi

echo -e "${GREEN}Gateway Demo Status${NC}"
echo "==================="
echo "URL: http://$GATEWAY_IP"
echo "API: http://$GATEWAY_IP/api/status"
echo "Health: http://$GATEWAY_IP/health"
echo ""
echo -e "${YELLOW}Testing connectivity...${NC}"

# Test health endpoint
if curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://"$GATEWAY_IP"/health; then
    echo -e "${GREEN}✓ Health check passed${NC}"
else
    echo -e "${RED}✗ Health check failed${NC}"
fi