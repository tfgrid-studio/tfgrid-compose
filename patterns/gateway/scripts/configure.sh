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

echo -e "${GREEN}ThreeFold Grid Gateway Configuration${NC}"
echo "====================================="

# Check if we're running on the gateway VM
if [[ ! -f /etc/wireguard/gateway.conf ]]; then
    echo -e "${RED}ERROR: This script should be run on the gateway VM${NC}"
    echo "First deploy infrastructure, then SSH to the gateway VM and run this script."
    exit 1
fi

# Enable IP forwarding
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

# Make forwarding persistent
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf

# Install required packages
echo -e "${YELLOW}Installing required packages...${NC}"
apt update
apt install -y nftables wireguard jq curl

# Create NAT table
echo -e "${YELLOW}Setting up NAT rules...${NC}"
nft add table inet gateway_nat
nft add chain inet gateway_nat prerouting { type nat hook prerouting priority -100; }
nft add chain inet gateway_nat postrouting { type nat hook postrouting priority 100; }

# Enable masquerading for internal network
nft add rule inet gateway_nat postrouting ip saddr 10.1.0.0/16 oifname "eth0" masquerade

# Create firewall table
echo -e "${YELLOW}Setting up firewall rules...${NC}"
nft add table inet firewall
nft add chain inet firewall input { type filter hook input priority 0; policy drop; }
nft add chain inet firewall forward { type filter hook forward priority 0; policy drop; }

# Allow established connections
nft add rule inet firewall input ct state established,related accept
nft add rule inet firewall forward ct state established,related accept

# Allow loopback
nft add rule inet firewall input iifname "lo" accept

# Allow SSH from anywhere (you may want to restrict this)
nft add rule inet firewall input tcp dport 22 accept

# Allow HTTP/HTTPS
nft add rule inet firewall input tcp dport { 80, 443 } accept

# Allow WireGuard
nft add rule inet firewall input udp dport 51820 accept
nft add rule inet firewall input iifname "gateway" accept

# Allow forwarding between interfaces
nft add rule inet firewall forward iifname "gateway" oifname "eth0" accept
nft add rule inet firewall forward iifname "eth0" oifname "gateway" accept

# Log dropped packets
nft add rule inet firewall input log prefix "Dropped input: " drop
nft add rule inet firewall forward log prefix "Dropped forward: " drop

# Make nftables rules persistent
echo -e "${YELLOW}Making firewall rules persistent...${NC}"
nft list ruleset > /etc/nftables.conf
systemctl enable nftables
systemctl start nftables

# Configure Mycelium if available
if command -v mycelium >/dev/null 2>&1; then
    echo -e "${YELLOW}Configuring Mycelium...${NC}"
    systemctl enable mycelium
    systemctl start mycelium

    # Wait for Mycelium to get an IP
    echo "Waiting for Mycelium IP..."
    for i in {1..30}; do
        MYCELIUM_IP=$(mycelium inspect --json 2>/dev/null | jq -r .address 2>/dev/null || echo "")
        if [[ -n "$MYCELIUM_IP" && "$MYCELIUM_IP" != "null" ]]; then
            echo -e "${GREEN}Mycelium IP: $MYCELIUM_IP${NC}"
            break
        fi
        sleep 2
    done
fi

# Test connectivity
echo -e "${YELLOW}Testing connectivity...${NC}"

# Test internet connectivity
if curl -s --connect-timeout 5 https://www.google.com >/dev/null; then
    echo -e "${GREEN}✓ Internet connectivity OK${NC}"
else
    echo -e "${RED}✗ Internet connectivity failed${NC}"
fi

# Show current configuration
echo ""
echo -e "${GREEN}Gateway Configuration Summary:${NC}"
echo "================================"

echo "IP Forwarding:"
sysctl net.ipv4.ip_forward
sysctl net.ipv6.conf.all.forwarding

echo ""
echo "NFT Rules:"
nft list table inet gateway_nat
nft list table inet firewall

echo ""
echo "WireGuard Status:"
wg show gateway 2>/dev/null || echo "WireGuard not active"

echo ""
echo -e "${GREEN}Gateway configuration completed!${NC}"
echo ""
echo "You can now:"
echo "- Access internal services through the gateway's public IP"
echo "- Use WireGuard to securely connect to internal VMs"
echo "- Leverage Mycelium for encrypted IPv6 communication"