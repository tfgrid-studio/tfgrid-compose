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

# Create systemd service
echo "📝 Creating systemd service..."
cat > /etc/systemd/system/tfgrid-ai-agent.service << 'EOF'
[Unit]
Description=TFGrid AI Agent Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ai-agent
ExecStart=/opt/ai-agent/scripts/agent-loop.sh /opt/ai-agent-projects
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/ai-agent/output.log
StandardError=append:/var/log/ai-agent/error.log

[Install]
WantedBy=multi-user.target
EOF

# Create log directory
echo "📁 Creating log directory..."
mkdir -p /var/log/ai-agent
chmod 755 /var/log/ai-agent

# Reload systemd
echo "🔄 Reloading systemd..."
systemctl daemon-reload

# Enable and start service
echo "▶️  Starting service..."
systemctl enable tfgrid-ai-agent
systemctl start tfgrid-ai-agent

echo ""
echo "✅ Configuration complete!"
echo "=========================================="