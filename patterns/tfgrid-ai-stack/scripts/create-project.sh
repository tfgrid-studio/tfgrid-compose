#!/bin/bash

# TFGrid AI Stack - Create Project Script (MVP)
# Version: 0.12.0-dev

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INFRA_DIR="$PROJECT_ROOT/infrastructure"

# Get description
if [ -z "$1" ]; then
    echo "Usage: $0 <description>"
    echo "Example: $0 \"portfolio website with dark mode\""
    exit 1
fi

DESCRIPTION="$1"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     TFGrid AI Stack - Create Project                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Description: $DESCRIPTION"
echo ""

# Get AI Agent IP
cd "$INFRA_DIR"
if [ ! -f terraform.tfstate ]; then
    echo -e "${RED}✗${NC} No deployment found. Run ./scripts/deploy.sh first"
    exit 1
fi

AI_AGENT_IP=$(terraform output -raw ai_agent_ip 2>/dev/null)
GATEWAY_IP=$(terraform output -raw gateway_ip 2>/dev/null)

if [ -z "$AI_AGENT_IP" ]; then
    echo -e "${RED}✗${NC} Could not get AI Agent IP"
    exit 1
fi

# Check AI Agent API is running
if ! curl -sf -m 5 "http://$AI_AGENT_IP:8080/health" >/dev/null 2>&1; then
    echo -e "${RED}✗${NC} AI Agent API is not responding"
    echo "  Try: ssh root@$AI_AGENT_IP 'systemctl status ai-agent-api'"
    exit 1
fi

# Create project
echo -e "${YELLOW}→${NC} Creating project..."
START_TIME=$(date +%s)

RESPONSE=$(curl -sf -X POST "http://$AI_AGENT_IP:8080/api/v1/projects" \
    -H "Content-Type: application/json" \
    -d "{\"description\":\"$DESCRIPTION\"}" 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}✗${NC} Failed to create project"
    echo "Error: $RESPONSE"
    exit 1
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Parse response
PROJECT_ID=$(echo "$RESPONSE" | jq -r '.project_id')
REPO_URL=$(echo "$RESPONSE" | jq -r '.repo_url')
LIVE_URL=$(echo "$RESPONSE" | jq -r '.live_url')

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Project Created Successfully!                          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Project ID: $PROJECT_ID"
echo "Description: $DESCRIPTION"
echo ""
echo "📁 Repository: $REPO_URL"
echo "🌐 Live Site: $LIVE_URL"
echo "⏱️  Duration: ${DURATION}s"
echo ""
echo "Next steps:"
echo "  - View site: curl $LIVE_URL"
echo "  - Clone repo: git clone $REPO_URL"
echo "  - List projects: ./scripts/list-projects.sh"
echo "  - Monitor: ssh root@$AI_AGENT_IP 'journalctl -u ai-agent-api -f'"