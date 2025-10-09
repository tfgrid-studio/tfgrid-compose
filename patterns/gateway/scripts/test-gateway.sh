#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
INFRASTRUCTURE_DIR="$PROJECT_DIR/infrastructure"

echo -e "${BLUE}ThreeFold Grid Gateway Testing Suite${NC}"
echo "======================================"

# Get gateway IP
GATEWAY_IP=$(cd "$INFRASTRUCTURE_DIR" && tofu output -json gateway_public_ip 2>/dev/null | jq -r . 2>/dev/null | sed 's|/.*||' || echo "")

if [[ -z "$GATEWAY_IP" || "$GATEWAY_IP" == "null" ]]; then
    echo -e "${RED}ERROR: Gateway IP not found. Have you deployed infrastructure yet?${NC}"
    echo "Run 'make infrastructure' first."
    exit 1
fi

echo -e "${GREEN}Testing Gateway: $GATEWAY_IP${NC}"
echo ""

# Test 1: Basic connectivity
echo -e "${YELLOW}Test 1: Basic Connectivity${NC}"
if ping -c 3 -W 5 "$GATEWAY_IP" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Gateway is reachable via ICMP${NC}"
else
    echo -e "${RED}❌ Gateway is not reachable via ICMP${NC}"
fi

# Test 2: SSH connectivity
echo -e "${YELLOW}Test 2: SSH Connectivity${NC}"
if nc -z -w5 "$GATEWAY_IP" 22 >/dev/null 2>&1; then
    echo -e "${GREEN}✅ SSH port (22) is open${NC}"
else
    echo -e "${RED}❌ SSH port (22) is not accessible${NC}"
fi

# Test 3: HTTP connectivity (demo page)
echo -e "${YELLOW}Test 3: HTTP Connectivity${NC}"
if curl -s --max-time 10 --connect-timeout 5 "http://$GATEWAY_IP" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ HTTP port (80) is responding${NC}"

    # Test 4: Demo page content
    echo -e "${YELLOW}Test 4: Demo Page Content${NC}"
    if curl -s "http://$GATEWAY_IP" | grep -q "ThreeFold Grid Gateway"; then
        echo -e "${GREEN}✅ Demo status page is working${NC}"
    else
        echo -e "${YELLOW}⚠️  Demo page exists but content may not be loaded${NC}"
    fi

    # Test 5: API endpoint
    echo -e "${YELLOW}Test 5: API Endpoint${NC}"
    if curl -s "http://$GATEWAY_IP/api/status" | jq . >/dev/null 2>&1; then
        echo -e "${GREEN}✅ JSON API is working${NC}"
    else
        echo -e "${YELLOW}⚠️  API endpoint exists but may not be responding${NC}"
    fi

    # Test 6: Health check
    echo -e "${YELLOW}Test 6: Health Check${NC}"
    if curl -s "http://$GATEWAY_IP/health" | grep -q "OK"; then
        echo -e "${GREEN}✅ Health check is working${NC}"
    else
        echo -e "${YELLOW}⚠️  Health check exists but may not be responding${NC}"
    fi
else
    echo -e "${RED}❌ HTTP port (80) is not responding${NC}"
    echo -e "${YELLOW}💡 Tip: Run 'make demo' to deploy the demo status page${NC}"
fi

# Test 7: Firewall status (via SSH if possible)
echo -e "${YELLOW}Test 7: Firewall Status${NC}"
if command -v ssh >/dev/null 2>&1; then
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$GATEWAY_IP" "sudo nft list ruleset | head -5" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Firewall (nftables) is accessible${NC}"
    else
        echo -e "${YELLOW}⚠️  Cannot verify firewall status (SSH may require key setup)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  SSH not available for firewall verification${NC}"
fi

echo ""
echo -e "${BLUE}Testing Summary:${NC}"
echo "==============="
echo -e "Gateway IP: ${GREEN}$GATEWAY_IP${NC}"
echo -e "Demo URL: ${GREEN}http://$GATEWAY_IP${NC}"
echo -e "API URL: ${GREEN}http://$GATEWAY_IP/api/status${NC}"
echo ""
echo -e "${GREEN}🎉 Gateway testing completed!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. If demo page is not working: Run 'make demo'"
echo "2. To check firewall rules: Run 'make connect' then 'sudo nft list ruleset'"
echo "3. To monitor gateway: Visit the demo page for real-time status"