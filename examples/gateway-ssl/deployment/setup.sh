#!/bin/bash
# Gateway test - Setup hook

set -e

echo "Setting up gateway test application..."

# Install nginx if not present
if ! command -v nginx &> /dev/null; then
    echo "Installing nginx..."
    apt-get update
    apt-get install -y nginx
fi

# Create web root
mkdir -p /var/www/html

echo "Setup complete!"
