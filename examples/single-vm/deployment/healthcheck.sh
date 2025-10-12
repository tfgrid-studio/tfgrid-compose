#!/bin/bash
# Single VM - Health check hook
set -e

# Check nginx is running
if ! systemctl is-active --quiet nginx; then
    echo "❌ Nginx is not running"
    exit 1
fi

# Check if website is accessible
if curl -sf http://localhost/ > /dev/null; then
    echo "✅ Website is healthy"
    exit 0
else
    echo "❌ Website is not responding"
    exit 1
fi
