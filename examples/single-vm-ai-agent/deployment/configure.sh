#!/bin/bash
# AI Agent - Configure hook (minimal configuration, AI agent configured via Ansible)
set -e

echo "=========================================="
echo "  CONFIGURE: Setting up AI Agent system"
echo "=========================================="

# Display system info
echo "System Information:"
echo "  Hostname: $(hostname)"
echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "  Kernel: $(uname -r)"
echo "  CPU cores: $(nproc)"
echo "  Memory: $(free -h | awk 'NR==2 {print $2}')"
echo ""

# Create AI agent workspace directory
echo "Creating AI agent workspace..."
mkdir -p /opt/ai-agent-projects
chmod 755 /opt/ai-agent-projects

echo ""
echo "✅ Configuration complete!"
echo "=========================================="