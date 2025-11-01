#!/bin/bash
# Deployment ID System - Docker-style unique deployment identifiers

set -e

# Deployment registry file
DEPLOYMENT_REGISTRY="$HOME/.config/tfgrid-compose/deployments.yaml"

# Initialize deployment registry
init_deployment_registry() {
    mkdir -p "$(dirname "$DEPLOYMENT_REGISTRY")"
    
    if [ ! -f "$DEPLOYMENT_REGISTRY" ]; then
        echo "deployments: {}" > "$DEPLOYMENT_REGISTRY"
    fi
}

# Generate unique deployment ID (Docker-style)
generate_deployment_id() {
    # Generate 16-character hex string (like Docker container IDs)
    openssl rand -hex 8
}

# Validate deployment ID format
is_deployment_id() {
    local identifier="$1"
    [[ "$identifier" =~ ^[a-f0-9]{16}$ ]]
}

# Register deployment in registry
register_deployment() {
    local deployment_id="$1"
    local app_name="$2"
    local state_dir="$3"
    local vm_ip="$4"
    
    init_deployment_registry
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Use yq if available, otherwise use simple sed/awk
    if command_exists yq; then
        yq eval ".deployments.\"$deployment_id\" = {
            app_name: \"$app_name\",
            state_dir: \"$state_dir\",
            vm_ip: \"$vm_ip\",
            created_at: \"$timestamp\",
            status: \"active\"
        }" "$DEPLOYMENT_REGISTRY" > "${DEPLOYMENT_REGISTRY}.tmp"
        mv "${DEPLOYMENT_REGISTRY}.tmp" "$DEPLOYMENT_REGISTRY"
    else
        # Fallback for systems without yq
        echo "Warning: yq not available, using basic YAML registry" >&2
        # For now, create a simple text-based registry
        echo "$deployment_id|$app_name|$state_dir|$vm_ip|$timestamp|active" >> "${DEPLOYMENT_REGISTRY}.tmp"
        if [ ! -f "${DEPLOYMENT_REGISTRY}.backup" ]; then
            cp "$DEPLOYMENT_REGISTRY" "${DEPLOYMENT_REGISTRY}.backup" 2>/dev/null || true
        fi
    fi
}

# Unregister deployment from registry
unregister_deployment() {
    local deployment_id="$1"
    
    init_deployment_registry
    
    if command_exists yq; then
        yq eval "del(.deployments.\"$deployment_id\")" "$DEPLOYMENT_REGISTRY" > "${DEPLOYMENT_REGISTRY}.tmp"
        mv "${DEPLOYMENT_REGISTRY}.tmp" "$DEPLOYMENT_REGISTRY"
    else
        # Fallback: remove from text registry
        if [ -f "${DEPLOYMENT_REGISTRY}.tmp" ]; then
            grep -v "^$deployment_id|" "$DEPLOYMENT_REGISTRY" > "${DEPLOYMENT_REGISTRY}.tmp" || true
            mv "${DEPLOYMENT_REGISTRY}.tmp" "$DEPLOYMENT_REGISTRY"
        fi
    fi
}

# Get deployment by ID
get_deployment_by_id() {
    local deployment_id="$1"
    
    init_deployment_registry
    
    if command_exists yq; then
        yq eval ".deployments.\"$deployment_id\" // null" "$DEPLOYMENT_REGISTRY"
    else
        # Fallback: search in text registry
        local line=$(grep "^$deployment_id|" "$DEPLOYMENT_REGISTRY" 2>/dev/null || echo "")
        if [ -n "$line" ]; then
            echo "$line" | awk -F'|' '{print "id:" $1 "\napp_name:" $2 "\nstate_dir:" $3 "\nvm_ip:" $4 "\ncreated_at:" $5 "\nstatus:" $6}'
        fi
    fi
}

# Get active deployment for app name
get_active_deployment_for_app() {
    local app_name="$1"
    
    init_deployment_registry
    
    if command_exists yq; then
        yq eval ".deployments | to_entries | .[] | select(.value.app_name == \"$app_name\" and .value.status == \"active\") | .key" "$DEPLOYMENT_REGISTRY" | head -1
    else
        # Fallback: search in text registry
        local line=$(grep "|$app_name|.*|.*|active$" "$DEPLOYMENT_REGISTRY" 2>/dev/null | head -1 || echo "")
        if [ -n "$line" ]; then
            echo "$line" | cut -d'|' -f1
        fi
    fi
}

# Get all deployments
get_all_deployments() {
    init_deployment_registry
    
    if command_exists yq; then
        yq eval ".deployments | to_entries | .[] | \"\(.key)|\(.value.app_name)|\(.value.vm_ip)|\(.value.status)|\(.value.created_at)\"" "$DEPLOYMENT_REGISTRY"
    else
        # Fallback: show text registry
        cat "$DEPLOYMENT_REGISTRY" 2>/dev/null || echo ""
    fi
}

# Update deployment status
update_deployment_status() {
    local deployment_id="$1"
    local status="$2"
    
    init_deployment_registry
    
    if command_exists yq; then
        yq eval ".deployments.\"$deployment_id\".status = \"$status\"" "$DEPLOYMENT_REGISTRY" > "${DEPLOYMENT_REGISTRY}.tmp"
        mv "${DEPLOYMENT_REGISTRY}.tmp" "$DEPLOYMENT_REGISTRY"
    else
        # Fallback: update in text registry
        if [ -f "${DEPLOYMENT_REGISTRY}.tmp" ]; then
            sed "s/^$deployment_id|/|;s/|active$/|$status/" "$DEPLOYMENT_REGISTRY" > "${DEPLOYMENT_REGISTRY}.tmp" 2>/dev/null || true
            mv "${DEPLOYMENT_REGISTRY}.tmp" "$DEPLOYMENT_REGISTRY"
        fi
    fi
}

# Resolve deployment identifier (ID or app name)
resolve_deployment() {
    local identifier="$1"
    
    # If it looks like a deployment ID, search by ID
    if is_deployment_id "$identifier"; then
        local deployment_id="$identifier"
        if [ -n "$(get_deployment_by_id "$deployment_id")" ]; then
            echo "$deployment_id"
            return 0
        fi
    fi
    
    # Otherwise, search for active deployment with this app name
    local deployment_id=$(get_active_deployment_for_app "$identifier")
    if [ -n "$deployment_id" ]; then
        echo "$deployment_id"
        return 0
    fi
    
    return 1
}

# List deployments in Docker-style format
list_deployments_docker_style() {
    echo "Deployments (Docker-style):"
    echo ""
    
    local deployments=$(get_all_deployments)
    if [ -z "$deployments" ]; then
        echo "(no deployments found)"
        return 0
    fi
    
    echo "CONTAINER ID    APP NAME           STATUS          IP ADDRESS"
    echo "─────────────────────────────────────────────────────────────────"
    
    if command_exists yq; then
        echo "$deployments" | while IFS='|' read -r deployment_id app_name vm_ip status created_at; do
            printf "%-16s %-19s %-14s %s\n" "$deployment_id" "$app_name" "$status" "${vm_ip:-N/A}"
        done
    else
        echo "$deployments" | while IFS='|' read -r deployment_id app_name vm_ip status created_at; do
            printf "%-16s %-19s %-14s %s\n" "$deployment_id" "$app_name" "$status" "${vm_ip:-N/A}"
        done
    fi
}

# Export functions for use in other scripts
export -f init_deployment_registry
export -f generate_deployment_id
export -f is_deployment_id
export -f register_deployment
export -f unregister_deployment
export -f get_deployment_by_id
export -f get_active_deployment_for_app
export -f get_all_deployments
export -f update_deployment_status
export -f resolve_deployment
export -f list_deployments_docker_style

# Initialize on source
if [ -z "$DEPLOYMENT_ID_INITIALIZED" ]; then
    init_deployment_registry
    DEPLOYMENT_ID_INITIALIZED=1
fi