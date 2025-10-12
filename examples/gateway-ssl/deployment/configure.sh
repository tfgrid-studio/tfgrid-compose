#!/bin/bash
# Gateway test - Configure hook

set -e

echo "Configuring gateway test application..."

# Copy index.html to web root
if [ -f "../index.html" ]; then
    cp ../index.html /var/www/html/index.html
    echo "Copied index.html to /var/www/html/"
elif [ -f "index.html" ]; then
    cp index.html /var/www/html/index.html
    echo "Copied index.html to /var/www/html/"
else
    echo "Warning: index.html not found, creating default..."
    cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>TFGrid Gateway Test</title></head>
<body><h1>Gateway Test - Deployed Successfully!</h1></body></html>
EOF
fi

# Set permissions
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Start nginx
systemctl enable nginx
systemctl restart nginx

echo "Configuration complete!"
