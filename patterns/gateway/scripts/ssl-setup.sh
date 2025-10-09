#!/bin/bash

# SSL Setup Script for ThreeFold Grid Gateway
# This script handles SSL certificate setup using Let's Encrypt

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

# Default values
DOMAIN_NAME=${DOMAIN_NAME:-}
ENABLE_SSL=${ENABLE_SSL:-false}
GATEWAY_TYPE=${GATEWAY_TYPE:-gateway_proxy}
SSL_EMAIL=${SSL_EMAIL:-admin@$DOMAIN_NAME}
SSL_STAGING=${SSL_STAGING:-false}

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if domain is provided
    if [ -z "$DOMAIN_NAME" ]; then
        log_error "DOMAIN_NAME environment variable is required"
        log_error "Example: export DOMAIN_NAME=mygateway.example.com"
        exit 1
    fi

    # Check if SSL is enabled
    if [ "$ENABLE_SSL" != "true" ]; then
        log_error "ENABLE_SSL must be set to 'true'"
        log_error "Example: export ENABLE_SSL=true"
        exit 1
    fi

    # Check if using proxy gateway (SSL requires nginx for termination)
    if [ "$GATEWAY_TYPE" != "gateway_proxy" ]; then
        log_error "SSL requires gateway_proxy for proper SSL termination"
        log_error "Current gateway type: $GATEWAY_TYPE"
        echo ""
        log_info "To fix this:"
        echo "1. Update your .env file:"
        echo "   GATEWAY_TYPE=gateway_proxy"
        echo "2. Redeploy with: make demo"
        echo "3. Then run SSL setup: make ssl-setup"
        echo ""
        log_info "Or deploy fresh with SSL: make ssl-demo"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Verify DNS configuration
verify_dns() {
    log_info "Verifying DNS configuration for $DOMAIN_NAME..."

    # Get gateway IP from Terraform outputs or inventory
    GATEWAY_IP=""
    if [ -f "$PROJECT_DIR/platform/inventory.ini" ]; then
        GATEWAY_IP=$(grep -oP 'ansible_host=\K[^ ]+' "$PROJECT_DIR/platform/inventory.ini" | head -1)
    fi

    if [ -z "$GATEWAY_IP" ]; then
        log_warning "Could not determine gateway IP from inventory"
        log_warning "Please ensure your domain $DOMAIN_NAME points to your gateway's IPv4 address"
        return
    fi

    # Check DNS resolution
    DOMAIN_IP=$(dig +short A "$DOMAIN_NAME" 2>/dev/null | head -1)

    if [ -z "$DOMAIN_IP" ]; then
        log_error "Domain $DOMAIN_NAME does not resolve to any IP address"
        log_error "Please check your DNS configuration"
        exit 1
    fi

    if [ "$DOMAIN_IP" != "$GATEWAY_IP" ]; then
        log_error "Domain $DOMAIN_NAME resolves to $DOMAIN_IP but gateway is at $GATEWAY_IP"
        log_error "Please update your DNS A record to point to $GATEWAY_IP"
        exit 1
    fi

    log_success "DNS verification passed: $DOMAIN_NAME → $GATEWAY_IP"
}

# Setup SSL certificates
setup_ssl() {
    log_info "Setting up SSL certificates for $DOMAIN_NAME..."

    # Check if we're running on the gateway
    if [ ! -f /etc/os-release ] || ! grep -q "Ubuntu\|Debian" /etc/os-release; then
        log_error "This script should be run on the gateway VM"
        log_error "SSH into your gateway and run this script there"
        exit 1
    fi

    # Install certbot if not present
    if ! command -v certbot &> /dev/null; then
        log_info "Installing certbot..."
        apt update
        apt install -y certbot python3-certbot-nginx
    fi

    # Check if certificate already exists
    if [ -d "/etc/letsencrypt/live/$DOMAIN_NAME" ]; then
        log_warning "SSL certificate already exists for $DOMAIN_NAME"
        log_info "Checking certificate validity..."

        # Check certificate expiry
        if openssl x509 -checkend 86400 -noout -in "/etc/letsencrypt/live/$DOMAIN_NAME/cert.pem" 2>/dev/null; then
            log_success "Certificate is valid for at least 24 more hours"
            return
        else
            log_warning "Certificate expires soon, renewing..."
            certbot renew --cert-name "$DOMAIN_NAME"
            return
        fi
    fi

    # Obtain new certificate
    log_info "Obtaining SSL certificate for $DOMAIN_NAME..."

    # Stop nginx temporarily for HTTP-01 challenge
    if systemctl is-active --quiet nginx; then
        log_info "Stopping nginx for certificate challenge..."
        systemctl stop nginx
    fi

    # Determine certbot command
    CERTBOT_CMD="certbot certonly --standalone"
    if [ "$SSL_STAGING" = "true" ]; then
        CERTBOT_CMD="$CERTBOT_CMD --staging"
        log_warning "Using Let's Encrypt staging environment (test certificates)"
    fi

    # Get certificate
    if $CERTBOT_CMD -d "$DOMAIN_NAME" --agree-tos --email "$SSL_EMAIL" --non-interactive; then
        log_success "SSL certificate obtained successfully"
    else
        log_error "Failed to obtain SSL certificate"
        # Restart nginx if it was stopped
        if ! systemctl is-active --quiet nginx; then
            systemctl start nginx
        fi
        exit 1
    fi

    # Restart nginx
    systemctl start nginx
    log_success "Nginx restarted with SSL configuration"
}

# Main execution
main() {
    echo "ThreeFold Grid Gateway - SSL Setup"
    echo "=================================="

    check_prerequisites
    verify_dns
    setup_ssl

    echo ""
    log_success "SSL setup completed successfully!"
    echo ""
    echo "Your gateway is now available at:"
    echo "  HTTP:  http://$DOMAIN_NAME"
    echo "  HTTPS: https://$DOMAIN_NAME"
    echo ""
    echo "Test your SSL setup:"
    echo "  curl -I https://$DOMAIN_NAME"
    echo ""
    echo "Certificate details:"
    echo "  Issuer: Let's Encrypt"
    echo "  Auto-renewal: Enabled"
    echo "  Valid for: 90 days"
}

# Run main function
main "$@"