#!/bin/bash
# Gateway test - Health check hook

set -e

# Check if nginx is running
if ! systemctl is-active --quiet nginx; then
    echo "❌ Nginx is not running"
    exit 1
fi

# Check if the index.html is accessible
if curl -s -f http://localhost/ > /dev/null; then
    echo "✅ Application is healthy"
    exit 0
else
    echo "❌ Application is not responding"
    exit 1
fi
