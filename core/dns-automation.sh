#!/usr/bin/env bash
# DNS Automation Module
# Supports automatic DNS A record creation for Name.com, Cloudflare, and Namecheap
#
# Recommended providers (fully automated):
#   - name.com: API token auth, no IP restrictions
#   - cloudflare: API token auth, no IP restrictions
#
# Limited automation:
#   - namecheap: Requires manual IP whitelisting in dashboard before API works

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh" 2>/dev/null || true

# DNS Provider credentials (populated during interactive config)
declare -A DNS_CREDENTIALS

# Configure DNS provider credentials
configure_dns_provider() {
    local provider="$1"
    
    case "$provider" in
        # Recommended: Name.com (fully automated, no IP restrictions)
        "name.com"|"namecom")
            echo "  → Name.com API Configuration (recommended)"
            read -p "    Username: " namecom_user
            read -s -p "    API Token: " namecom_token
            echo ""
            
            if [ -z "$namecom_user" ] || [ -z "$namecom_token" ]; then
                log_error "Name.com credentials are required"
                return 1
            fi
            
            DNS_CREDENTIALS["NAMECOM_USERNAME"]="$namecom_user"
            DNS_CREDENTIALS["NAMECOM_API_TOKEN"]="$namecom_token"
            export NAMECOM_USERNAME="$namecom_user"
            export NAMECOM_API_TOKEN="$namecom_token"
            ;;
        
        # Recommended: Cloudflare (fully automated, no IP restrictions)
        "cloudflare")
            echo "  → Cloudflare API Configuration (recommended)"
            read -s -p "    API Token: " cf_token
            echo ""
            
            if [ -z "$cf_token" ]; then
                log_error "Cloudflare API token is required"
                return 1
            fi
            
            DNS_CREDENTIALS["CLOUDFLARE_API_TOKEN"]="$cf_token"
            export CLOUDFLARE_API_TOKEN="$cf_token"
            ;;
        
        # Limited: Namecheap (requires manual IP whitelisting)
        "namecheap")
            echo "  → Namecheap API Configuration"
            echo ""
            log_warning "Namecheap is NOT fully automated - requires manual IP whitelisting."
            log_warning "Consider using name.com or cloudflare for fully automated DNS setup."
            echo ""
            echo "    Your current IP must be whitelisted at:"
            echo "    Namecheap → Profile → Tools → API Access → Whitelisted IPs"
            echo ""
            local current_ip=$(curl -s https://api.ipify.org 2>/dev/null || echo "unknown")
            echo "    Your current IP: $current_ip"
            echo ""
            read -p "    Have you whitelisted this IP? (y/N): " -n 1 -r ip_confirmed
            echo ""
            
            if [[ ! $ip_confirmed =~ ^[Yy]$ ]]; then
                log_warning "Please whitelist your IP first, then re-run with -i"
                log_info "Falling back to manual DNS setup"
                export DNS_PROVIDER="manual"
                return 0
            fi
            
            read -p "    API User: " namecheap_user
            read -s -p "    API Key: " namecheap_key
            echo ""
            
            if [ -z "$namecheap_user" ] || [ -z "$namecheap_key" ]; then
                log_error "Namecheap credentials are required"
                return 1
            fi
            
            DNS_CREDENTIALS["NAMECHEAP_API_USER"]="$namecheap_user"
            DNS_CREDENTIALS["NAMECHEAP_API_KEY"]="$namecheap_key"
            export NAMECHEAP_API_USER="$namecheap_user"
            export NAMECHEAP_API_KEY="$namecheap_key"
            ;;
            
        "manual"|"")
            log_info "Manual DNS configuration selected"
            return 0
            ;;
            
        *)
            log_error "Unknown DNS provider: $provider"
            return 1
            ;;
    esac
    
    log_success "DNS provider configured: $provider"
    return 0
}

# Create DNS A record using Name.com API
create_namecom_record() {
    local domain="$1"
    local ip="$2"
    local username="${NAMECOM_USERNAME}"
    local token="${NAMECOM_API_TOKEN}"
    
    if [ -z "$username" ] || [ -z "$token" ]; then
        log_error "Name.com credentials not configured"
        return 1
    fi
    
    # Extract subdomain and root domain
    local root_domain=$(echo "$domain" | rev | cut -d. -f1-2 | rev)
    local subdomain=$(echo "$domain" | sed "s/\.$root_domain$//" | sed "s/$root_domain$//")
    subdomain=${subdomain:-.}  # Use @ for root domain
    [ "$subdomain" = "$domain" ] && subdomain="@"
    
    log_info "Creating A record: $subdomain.$root_domain -> $ip"
    
    local response
    response=$(curl -s -X POST \
        -u "$username:$token" \
        -H "Content-Type: application/json" \
        -d "{\"host\":\"$subdomain\",\"type\":\"A\",\"answer\":\"$ip\",\"ttl\":300}" \
        "https://api.name.com/v4/domains/$root_domain/records")
    
    if echo "$response" | grep -q '"id"'; then
        log_success "DNS A record created successfully"
        return 0
    else
        log_error "Failed to create DNS record: $response"
        return 1
    fi
}

# Create DNS A record using Namecheap API
create_namecheap_record() {
    local domain="$1"
    local ip="$2"
    local api_user="${NAMECHEAP_API_USER}"
    local api_key="${NAMECHEAP_API_KEY}"
    
    if [ -z "$api_user" ] || [ -z "$api_key" ]; then
        log_error "Namecheap credentials not configured"
        return 1
    fi
    
    # Extract SLD and TLD
    local tld=$(echo "$domain" | rev | cut -d. -f1 | rev)
    local sld=$(echo "$domain" | rev | cut -d. -f2 | rev)
    local subdomain=$(echo "$domain" | sed "s/\.$sld\.$tld$//" | sed "s/$sld\.$tld$//")
    subdomain=${subdomain:-@}
    
    # Get client IP for API whitelist
    local client_ip=$(curl -s https://api.ipify.org)
    
    log_info "Creating A record: $subdomain.$sld.$tld -> $ip"
    
    local response
    response=$(curl -s "https://api.namecheap.com/xml.response" \
        -d "ApiUser=$api_user" \
        -d "ApiKey=$api_key" \
        -d "UserName=$api_user" \
        -d "ClientIp=$client_ip" \
        -d "Command=namecheap.domains.dns.setHosts" \
        -d "SLD=$sld" \
        -d "TLD=$tld" \
        -d "HostName1=$subdomain" \
        -d "RecordType1=A" \
        -d "Address1=$ip" \
        -d "TTL1=300")
    
    if echo "$response" | grep -q 'Status="OK"'; then
        log_success "DNS A record created successfully"
        return 0
    else
        log_error "Failed to create DNS record"
        log_error "Response: $response"
        return 1
    fi
}

# Create DNS A record using Cloudflare API
create_cloudflare_record() {
    local domain="$1"
    local ip="$2"
    local token="${CLOUDFLARE_API_TOKEN}"
    
    if [ -z "$token" ]; then
        log_error "Cloudflare API token not configured"
        return 1
    fi
    
    # Extract root domain (zone)
    local root_domain=$(echo "$domain" | rev | cut -d. -f1-2 | rev)
    local subdomain=$(echo "$domain" | sed "s/\.$root_domain$//" | sed "s/$root_domain$//")
    subdomain=${subdomain:-@}
    
    # Get zone ID
    log_info "Looking up Cloudflare zone for $root_domain..."
    local zone_response
    zone_response=$(curl -s -X GET \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones?name=$root_domain")
    
    local zone_id=$(echo "$zone_response" | jq -r '.result[0].id // empty')
    
    if [ -z "$zone_id" ]; then
        log_error "Could not find Cloudflare zone for $root_domain"
        return 1
    fi
    
    log_info "Creating A record: $domain -> $ip"
    
    local response
    response=$(curl -s -X POST \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"A\",\"name\":\"$domain\",\"content\":\"$ip\",\"ttl\":300,\"proxied\":false}" \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records")
    
    if echo "$response" | jq -e '.success' | grep -q 'true'; then
        log_success "DNS A record created successfully"
        return 0
    else
        local error=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_error "Failed to create DNS record: $error"
        return 1
    fi
}

# Main function to create DNS record based on configured provider
create_dns_record() {
    local domain="$1"
    local ip="$2"
    local provider="${DNS_PROVIDER:-manual}"
    
    if [ -z "$domain" ] || [ -z "$ip" ]; then
        log_error "Domain and IP are required"
        return 1
    fi
    
    log_info "Setting up DNS for $domain -> $ip"
    
    case "$provider" in
        "name.com"|"namecom")
            create_namecom_record "$domain" "$ip"
            ;;
        "cloudflare")
            create_cloudflare_record "$domain" "$ip"
            ;;
        "namecheap")
            create_namecheap_record "$domain" "$ip"
            ;;
        "manual"|"")
            echo ""
            log_warning "Manual DNS configuration required"
            echo ""
            echo "  Please create an A record with your DNS provider:"
            echo ""
            echo "    Domain: $domain"
            echo "    Type:   A"
            echo "    Value:  $ip"
            echo "    TTL:    300 (or your preference)"
            echo ""
            echo "  After creating the record, wait 1-5 minutes for propagation."
            echo ""
            return 0
            ;;
        *)
            log_error "Unknown DNS provider: $provider"
            return 1
            ;;
    esac
}

# Verify DNS propagation
verify_dns_propagation() {
    local domain="$1"
    local expected_ip="$2"
    local max_attempts="${3:-30}"
    local wait_seconds="${4:-10}"
    
    log_info "Verifying DNS propagation for $domain..."
    
    for ((i=1; i<=max_attempts; i++)); do
        local resolved_ip=$(dig +short "$domain" A 2>/dev/null | head -1)
        
        if [ "$resolved_ip" = "$expected_ip" ]; then
            log_success "DNS propagated: $domain -> $resolved_ip"
            return 0
        fi
        
        if [ $i -lt $max_attempts ]; then
            echo "  Attempt $i/$max_attempts: waiting for DNS propagation..."
            sleep $wait_seconds
        fi
    done
    
    log_warning "DNS not yet propagated after $max_attempts attempts"
    log_info "Current resolution: $domain -> ${resolved_ip:-none}"
    log_info "Expected: $expected_ip"
    return 1
}

# Export functions
export -f configure_dns_provider 2>/dev/null || true
export -f create_dns_record 2>/dev/null || true
export -f verify_dns_propagation 2>/dev/null || true
