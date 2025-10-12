#!/bin/bash
# Single VM - Setup hook
set -e

echo "Setting up nginx web server..."

# Install nginx
apt-get update
apt-get install -y nginx

# Create web root
mkdir -p /var/www/html

echo "✅ Setup complete!"
