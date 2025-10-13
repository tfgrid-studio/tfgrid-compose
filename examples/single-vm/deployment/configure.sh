#!/bin/bash
# Single VM - Configure hook
set -e

echo "=========================================="
echo "  CONFIGURE: Setting up system"
echo "=========================================="

# Display system info
echo "System Information:"
echo "  Hostname: $(hostname)"
echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "  Kernel: $(uname -r)"
echo "  CPU cores: $(nproc)"
echo "  Memory: $(free -h | awk 'NR==2 {print $2}')"
echo ""

# Copy index.html to web root
echo "Deploying website..."
cp ../index.html /var/www/html/index.html 2>/dev/null || echo "No index.html found, using default"

# Set permissions
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Configure and start nginx
echo "Starting nginx..."
systemctl enable nginx
systemctl restart nginx

# Verify nginx is running
sleep 2
if systemctl is-active --quiet nginx; then
    echo "✅ Nginx is running"
else
    echo "⚠️  Nginx status unclear"
fi

echo ""
echo "✅ Configuration complete!"
echo "=========================================="
