#!/bin/bash

# SSL Certificate Renewal Script for ThreeFold Grid Gateway
# This script handles SSL certificate renewal and management

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check certificate expiry
check_expiry() {
    local domain=$1
    local cert_path="/etc/letsencrypt/live/$domain/cert.pem"

    if [ ! -f "$cert_path" ]; then
        log_error "Certificate not found: $cert_path"
        return 1
    fi

    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_path" | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local now_epoch=$(date +%s)
    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

    echo "$days_left"
}

# Renew certificates
renew_certificates() {
    log_info "Checking SSL certificates for renewal..."

    if ! command -v certbot &> /dev/null; then
        log_error "certbot not found. Please install certbot first."
        exit 1
    fi

    # Dry run first
    log_info "Performing dry run..."
    if certbot renew --dry-run; then
        log_success "Dry run successful"
    else
        log_error "Dry run failed"
        exit 1
    fi

    # Actual renewal
    log_info "Renewing certificates..."
    if certbot renew; then
        log_success "Certificate renewal completed"

        # Reload nginx
        if systemctl is-active --quiet nginx; then
            systemctl reload nginx
            log_success "Nginx reloaded"
        fi
    else
        log_error "Certificate renewal failed"
        exit 1
    fi
}

# Show certificate status
show_status() {
    log_info "SSL Certificate Status:"

    if ! command -v certbot &> /dev/null; then
        log_error "certbot not installed"
        exit 1
    fi

    echo ""
    certbot certificates

    echo ""
    log_info "Certificate expiry check:"

    # Get list of certificates
    for cert in $(find /etc/letsencrypt/live -name "cert.pem" 2>/dev/null); do
        local domain=$(basename $(dirname $(dirname $cert)))
        local days_left=$(check_expiry "$domain")

        if [ "$days_left" -lt 30 ]; then
            log_error "$domain: Expires in $days_left days ⚠️"
        elif [ "$days_left" -lt 60 ]; then
            log_warning "$domain: Expires in $days_left days"
        else
            log_success "$domain: Expires in $days_left days ✅"
        fi
    done
}

# Main execution
main() {
    case "${1:-status}" in
        "renew")
            renew_certificates
            ;;
        "status")
            show_status
            ;;
        "check")
            # Just check expiry without full status
            for cert in $(find /etc/letsencrypt/live -name "cert.pem" 2>/dev/null); do
                local domain=$(basename $(dirname $(dirname $cert)))
                local days_left=$(check_expiry "$domain")
                echo "$domain: $days_left days"
            done
            ;;
        *)
            echo "Usage: $0 [status|renew|check]"
            echo "  status - Show certificate status and expiry"
            echo "  renew  - Renew certificates"
            echo "  check  - Check expiry days only"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"