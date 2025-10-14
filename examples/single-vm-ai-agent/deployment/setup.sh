#!/bin/bash
# AI Agent - Setup hook (minimal setup, AI agent installed via Ansible)
set -e

echo "=========================================="
echo "  SETUP: Installing base packages for AI Agent"
echo "=========================================="

# Update package cache
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
    tmux \
    screen \
    expect

echo ""
echo "✅ Setup complete!"
echo "   Installed: git, curl, wget, vim, htop, build-essential, python3, jq, tmux, screen, expect"
echo "=========================================="