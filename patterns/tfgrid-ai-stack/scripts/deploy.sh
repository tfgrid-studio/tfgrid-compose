#!/bin/bash

# TFGrid AI Stack - Deployment Script (MVP)
# Version: 0.12.0-dev

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INFRA_DIR="$PROJECT_ROOT/infrastructure"
PLATFORM_DIR="$PROJECT_ROOT/platform"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     TFGrid AI Stack - Deployment Script                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}→${NC} Checking prerequisites..."
    
    local missing=()
    
    command -v terraform >/dev/null 2>&1 || missing+=("terraform")
    command -v ansible >/dev/null 2>&1 || missing+=("ansible")
    command -v ssh >/dev/null 2>&1 || missing+=("ssh")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}✗${NC} Missing required tools: ${missing[*]}"
        echo "  Please install: ${missing[*]}"
        exit 1
    fi
    
    echo -e "${GREEN}✓${NC} All prerequisites installed"
}

# Initialize Terraform
terraform_init() {
    echo -e "${YELLOW}→${NC} Initializing Terraform..."
    cd "$INFRA_DIR"
    terraform init
    echo -e "${GREEN}✓${NC} Terraform initialized"
}

# Plan Terraform deployment
terraform_plan() {
    echo -e "${YELLOW}→${NC} Planning infrastructure..."
    cd "$INFRA_DIR"
    terraform plan -out=tfplan
    echo -e "${GREEN}✓${NC} Infrastructure plan created"
}

# Apply Terraform
terraform_apply() {
    echo -e "${YELLOW}→${NC} Deploying VMs (this may take 5-10 minutes)..."
    cd "$INFRA_DIR"
    terraform apply tfplan
    echo -e "${GREEN}✓${NC} VMs deployed"
}

# Get Terraform outputs
get_outputs() {
    echo -e "${YELLOW}→${NC} Getting deployment info..."
    cd "$INFRA_DIR"
    
    export GATEWAY_IP=$(terraform output -raw gateway_ip)
    export AI_AGENT_IP=$(terraform output -raw ai_agent_ip)
    export GITEA_IP=$(terraform output -raw gitea_ip)
    export GATEWAY_API_KEY=$(terraform output -raw gateway_api_key)
    
    echo -e "${GREEN}✓${NC} Deployment info retrieved"
    echo "  Gateway: $GATEWAY_IP"
    echo "  AI Agent: $AI_AGENT_IP"
    echo "  Gitea: $GITEA_IP"
}

# Generate Ansible inventory
generate_inventory() {
    echo -e "${YELLOW}→${NC} Generating Ansible inventory..."
    
    cat > "$PLATFORM_DIR/inventory.ini" <<EOF
[gateway]
gateway ansible_host=$GATEWAY_IP ansible_user=root

[ai_agent]
ai-agent ansible_host=$AI_AGENT_IP ansible_user=root

[gitea]
gitea ansible_host=$GITEA_IP ansible_user=root

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
gateway_api_key=$GATEWAY_API_KEY
gitea_admin_user=gitadmin
gitea_admin_password=$(cd "$INFRA_DIR" && terraform output -raw gitea_admin_password)
gitea_db_password=$(cd "$INFRA_DIR" && terraform output -raw gitea_db_password)
domain=${DOMAIN:-}
ssl_email=${SSL_EMAIL:-}
EOF
    
    echo -e "${GREEN}✓${NC} Ansible inventory created"
}

# Wait for VMs to be ready
wait_for_vms() {
    echo -e "${YELLOW}→${NC} Waiting for VMs to be ready..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$GATEWAY_IP "echo ready" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} VMs are ready"
            return 0
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 10
    done
    
    echo -e "${RED}✗${NC} VMs did not become ready in time"
    exit 1
}

# Run Ansible playbooks
run_ansible() {
    echo -e "${YELLOW}→${NC} Configuring VMs with Ansible (this may take 10-15 minutes)..."
    cd "$PLATFORM_DIR"
    
    ansible-playbook -i inventory.ini playbooks/site.yml
    
    echo -e "${GREEN}✓${NC} VMs configured"
}

# Deploy APIs
deploy_apis() {
    echo -e "${YELLOW}→${NC} Deploying Gateway API..."
    
    # Copy Gateway API to gateway VM
    scp -r "$PROJECT_ROOT/gateway-api" root@$GATEWAY_IP:/opt/
    ssh root@$GATEWAY_IP "cd /opt/gateway-api && npm install --production"
    
    # Create systemd service
    ssh root@$GATEWAY_IP "cat > /etc/systemd/system/gateway-api.service" <<'EOF'
[Unit]
Description=TFGrid Gateway API
After=network.target nginx.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/gateway-api
Environment="PORT=3000"
Environment="API_KEY=$GATEWAY_API_KEY"
ExecStart=/usr/bin/node src/index.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    ssh root@$GATEWAY_IP "systemctl daemon-reload && systemctl enable gateway-api && systemctl start gateway-api"
    
    echo -e "${GREEN}✓${NC} Gateway API deployed"
    
    echo -e "${YELLOW}→${NC} Deploying AI Agent API..."
    
    # Copy AI Agent API
    scp -r "$PROJECT_ROOT/ai-agent-api" root@$AI_AGENT_IP:/opt/
    ssh root@$AI_AGENT_IP "cd /opt/ai-agent-api && npm install --production"
    
    # Create systemd service
    ssh root@$AI_AGENT_IP "cat > /etc/systemd/system/ai-agent-api.service" <<EOF
[Unit]
Description=TFGrid AI Agent API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ai-agent-api
Environment="PORT=8080"
Environment="GATEWAY_IP=$GATEWAY_IP"
Environment="GATEWAY_API_KEY=$GATEWAY_API_KEY"
Environment="GITEA_IP=$GITEA_IP"
Environment="GITEA_ADMIN_USER=gitadmin"
Environment="GITEA_ADMIN_PASSWORD=$(cd "$INFRA_DIR" && terraform output -raw gitea_admin_password)"
ExecStart=/usr/bin/node src/index.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    ssh root@$AI_AGENT_IP "systemctl daemon-reload && systemctl enable ai-agent-api && systemctl start ai-agent-api"
    
    echo -e "${GREEN}✓${NC} AI Agent API deployed"
}

# Main deployment flow
main() {
    check_prerequisites
    terraform_init
    terraform_plan
    
    echo ""
    echo -e "${YELLOW}Ready to deploy. This will:${NC}"
    echo "  1. Create 3 VMs on ThreeFold Grid"
    echo "  2. Configure services (Nginx, Gitea, etc)"
    echo "  3. Deploy APIs"
    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled"
        exit 0
    fi
    
    terraform_apply
    get_outputs
    generate_inventory
    wait_for_vms
    run_ansible
    deploy_apis
    
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     Deployment Complete!                                   ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Access Information:"
    echo "  Gateway IP: $GATEWAY_IP"
    echo "  AI Agent IP: $AI_AGENT_IP"
    echo "  Gitea IP: $GITEA_IP"
    echo ""
    echo "Credentials saved in: $INFRA_DIR/.credentials"
    echo ""
    echo "Next steps:"
    echo "  1. Test health: $SCRIPT_DIR/health-check.sh"
    echo "  2. Create project: curl -X POST http://$AI_AGENT_IP:8080/api/v1/projects \\"
    echo "                       -H 'Content-Type: application/json' \\"
    echo "                       -d '{\"description\":\"hello world website\"}'"
    echo ""
}

main "$@"