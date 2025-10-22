#!/bin/bash

# TFGrid AI Stack - List Projects Script (MVP)
# Version: 0.12.0-dev

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INFRA_DIR="$PROJECT_ROOT/infrastructure"

# Get AI Agent IP
cd "$INFRA_DIR"
if [ ! -f terraform.tfstate ]; then
    echo "No deployment found. Run ./scripts/deploy.sh first"
    exit 1
fi

AI_AGENT_IP=$(terraform output -raw ai_agent_ip 2>/dev/null)

if [ -z "$AI_AGENT_IP" ]; then
    echo "Could not get AI Agent IP"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     TFGrid AI Stack - Projects                             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Get projects
PROJECTS=$(curl -sf "http://$AI_AGENT_IP:8080/api/v1/projects" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$PROJECTS" ]; then
    echo "Failed to fetch projects. Is AI Agent API running?"
    exit 1
fi

# Display projects
echo "$PROJECTS" | jq -r '.[] | 
"
Project: \(.id)
Description: \(.description)
Status: \(.status)
Repository: \(.repo_url // "N/A")
Live URL: \(.live_url // "N/A")
Created: \(.created_at)
Duration: \(.duration // 0)s
---"'

# Count projects
COUNT=$(echo "$PROJECTS" | jq '. | length')
echo ""
echo -e "${GREEN}Total projects: $COUNT${NC}"