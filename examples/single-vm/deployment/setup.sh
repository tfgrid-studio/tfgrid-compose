#!/bin/bash
# Single VM - Setup hook (matches external tfgrid-ai-agent foundation)
set -e

echo "=========================================="
echo "  SETUP: Installing base packages"
echo "=========================================="

# Update package cache (like external does)
echo "Updating apt cache..."
apt-get update

# Install base packages (matching external's package list)
echo "Installing base packages..."
apt-get install -y \
    git \
    curl \
    wget \
    vim \
    htop \
    build-essential \
    python3 \
    python3-pip \
    jq \
    nginx

# Create web root
mkdir -p /var/www/html

echo ""
echo "✅ Setup complete!"
echo "   Installed: git, curl, wget, vim, htop, build-essential, python3, jq, nginx"
echo "=========================================="
