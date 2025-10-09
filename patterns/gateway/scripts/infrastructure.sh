#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_DIR="$SCRIPT_DIR/.."
INFRASTRUCTURE_DIR="$PROJECT_DIR/infrastructure"

echo -e "${GREEN}ThreeFold Grid Gateway Infrastructure Deployment${NC}"
echo "=================================================="

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"

command -v tofu >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: tofu (OpenTofu) required but not found.${NC}"
    echo "Install from: https://opentofu.org/"
    exit 1
}

command -v jq >/dev/null 2>&1 || {
    echo -e "${RED}ERROR: jq required but not found.${NC}"
    echo "Install with: sudo apt install jq"
    exit 1
}

# Check if credentials file exists
if [[ ! -f "$INFRASTRUCTURE_DIR/credentials.auto.tfvars" ]]; then
    echo -e "${RED}ERROR: credentials.auto.tfvars not found!${NC}"
    echo "Copy $INFRASTRUCTURE_DIR/credentials.auto.tfvars.example to $INFRASTRUCTURE_DIR/credentials.auto.tfvars"
    echo "and configure your settings."
    exit 1
fi

# Check if mnemonic is set
if [[ -z "${TF_VAR_mnemonic:-}" ]]; then
    echo -e "${RED}ERROR: TF_VAR_mnemonic environment variable not set!${NC}"
    echo "Set it securely with:"
    echo "  set +o history"
    echo "  export TF_VAR_mnemonic='your_mnemonic_phrase'"
    echo "  set -o history"
    exit 1
fi

echo -e "${GREEN}Dependencies OK${NC}"

# Clean up previous deployment
echo -e "${YELLOW}Cleaning up previous deployment...${NC}"
cd "$INFRASTRUCTURE_DIR"
tofu destroy -auto-approve 2>/dev/null || true

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform/OpenTofu...${NC}"
tofu init

# Validate configuration
echo -e "${YELLOW}Validating configuration...${NC}"
tofu validate

# Plan deployment
echo -e "${YELLOW}Planning deployment...${NC}"
tofu plan -out=tfplan

# Apply deployment
echo -e "${YELLOW}Deploying infrastructure...${NC}"
tofu apply tfplan

# Extract important outputs
echo -e "${GREEN}Deployment completed!${NC}"
echo ""
echo -e "${GREEN}Gateway Information:${NC}"
echo "=================="

GATEWAY_IP=$(tofu output -json gateway_public_ip | jq -r .)
GATEWAY_WG_IP=$(tofu output -json gateway_wireguard_ip | jq -r .)
GATEWAY_MYCELIUM_IP=$(tofu output -json gateway_mycelium_ip | jq -r .)

echo "Public IPv4: $GATEWAY_IP"
echo "WireGuard IP: $GATEWAY_WG_IP"
echo "Mycelium IP: $GATEWAY_MYCELIUM_IP"
echo ""

# Show internal VM information
echo -e "${GREEN}Internal VMs:${NC}"
echo "============="

INTERNAL_WG_IPS=$(tofu output -json internal_wireguard_ips)
INTERNAL_MYCELIUM_IPS=$(tofu output -json internal_mycelium_ips)

echo "WireGuard IPs:"
echo "$INTERNAL_WG_IPS" | jq -r 'to_entries[] | "  \(.key): \(.value)"'
echo ""
echo "Mycelium IPs:"
echo "$INTERNAL_MYCELIUM_IPS" | jq -r 'to_entries[] | "  \(.key): \(.value)"'

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Run './scripts/wg.sh' to configure WireGuard on your local machine"
echo "2. SSH to gateway: ssh root@$GATEWAY_IP"
echo "3. Run './scripts/configure.sh' to set up gateway services"
echo ""
echo -e "${GREEN}Infrastructure deployment completed successfully!${NC}"