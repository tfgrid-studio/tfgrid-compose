#!/bin/bash
# Single VM - Configure hook
set -e

echo "Deploying website..."

# Copy index.html to web root
cp ../index.html /var/www/html/index.html 2>/dev/null || echo "No index.html found, using default"

# Set permissions
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Start nginx
systemctl enable nginx
systemctl restart nginx

echo "✅ Website deployed and nginx started!"
