#!/bin/bash

# TFGrid AI Stack - Health Check Script (MVP)
# Version: 0.12.0-dev

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INFRA_DIR="$PROJECT_ROOT/infrastructure"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     TFGrid AI Stack - Health Check                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get IPs from Terraform
cd "$INFRA_DIR"
if [ ! -f terraform.tfstate ]; then
    echo -e "${RED}✗${NC} No deployment found. Run ./scripts/deploy.sh first"
    exit 1
fi

GATEWAY_IP=$(terraform output -raw gateway_ip 2>/dev/null || echo "")
AI_AGENT_IP=$(terraform output -raw ai_agent_ip 2>/dev/null || echo "")
GITEA_IP=$(terraform output -raw gitea_ip 2>/dev/null || echo "")

if [ -z "$GATEWAY_IP" ]; then
    echo -e "${RED}✗${NC} Could not get deployment IPs"
    exit 1
fi

# Health check functions
check_vm() {
    local name=$1
    local ip=$2
    
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$ip "echo ready" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name VM: Online ($ip)"
        return 0
    else
        echo -e "${RED}✗${NC} $name VM: Offline ($ip)"
        return 1
    fi
}

check_http() {
    local name=$1
    local url=$2
    
    if curl -sf -m 5 "$url" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name: Healthy ($url)"
        return 0
    else
        echo -e "${RED}✗${NC} $name: Unhealthy ($url)"
        return 1
    fi
}

# Run checks
echo "1. Checking VM Status..."
check_vm "Gateway" "$GATEWAY_IP" || exit 1
check_vm "AI Agent" "$AI_AGENT_IP" || exit 1
check_vm "Gitea" "$GITEA_IP" || exit 1
echo ""

echo "2. Checking Service Status..."
check_http "Gateway API" "http://$GATEWAY_IP:3000/api/v1/health" || echo -e "${YELLOW}⚠${NC} Gateway API not yet deployed"
check_http "AI Agent API" "http://$AI_AGENT_IP:8080/health" || echo -e "${YELLOW}⚠${NC} AI Agent API not yet deployed"
check_http "Gitea" "http://$GITEA_IP:3000" || echo -e "${YELLOW}⚠${NC} Gitea not yet configured"
echo ""

echo "3. Checking Nginx..."
if ssh root@$GATEWAY_IP "systemctl is-active nginx" >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Nginx: Running"
else
    echo -e "${YELLOW}⚠${NC} Nginx: Not running"
fi
echo ""

echo "4. Checking Disk Space..."
for vm in "Gateway:$GATEWAY_IP" "AI-Agent:$AI_AGENT_IP" "Gitea:$GITEA_IP"; do
    IFS=':' read -r name ip <<< "$vm"
    usage=$(ssh root@$ip "df -h / | tail -1 | awk '{print \$5}' | tr -d '%'" 2>/dev/null || echo "0")
    if [ "$usage" -lt 80 ]; then
        echo -e "${GREEN}✓${NC} $name: ${usage}% used"
    else
        echo -e "${YELLOW}⚠${NC} $name: ${usage}% used (high)"
    fi
done
echo ""

echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Health check complete!${NC}"
echo ""
echo "Next steps:"
echo "  - Create your first project: ./scripts/create-project.sh \"hello world\""
echo "  - View all projects: ./scripts/list-projects.sh"
echo "  - Monitor logs: ssh root@$AI_AGENT_IP 'journalctl -u ai-agent-api -f'"
echo ""
echo "Dashboard URLs (if deployed):"
echo "  - Grafana: http://$GATEWAY_IP:3000"
echo "  - Prometheus: http://$GATEWAY_IP:9090"
echo "  - Gitea: http://$GITEA_IP:3000"