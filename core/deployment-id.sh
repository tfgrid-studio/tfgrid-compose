#!/bin/bash
# Deployment ID System - Docker-style unique deployment identifiers

set -e

# Source common utilities
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Deployment registry file
DEPLOYMENT_REGISTRY="$HOME/.config/tfgrid-compose/deployments.yaml"

# Initialize deployment registry
init_deployment_registry() {
    mkdir -p "$(dirname "$DEPLOYMENT_REGISTRY")"
    
    # Create or fix the deployments.yaml file
    if [ ! -f "$DEPLOYMENT_REGISTRY" ] || [ ! -s "$DEPLOYMENT_REGISTRY" ]; then
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

# Register deployment in registry with contract ID linkage
register_deployment() {
    local deployment_id="$1"
    local app_name="$2"
    local state_dir="$3"
    local vm_ip="$4"
    local contract_id="${5:-}"  # Optional contract ID from grid
    
    init_deployment_registry
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Use yq if available, otherwise use simple sed/awk
    if command_exists yq; then
        if [ -n "$contract_id" ]; then
            yq eval ".deployments.\"$deployment_id\" = {\"app_name\": \"$app_name\", \"state_dir\": \"$state_dir\", \"vm_ip\": \"$vm_ip\", \"contract_id\": \"$contract_id\", \"created_at\": \"$timestamp\", \"status\": \"active\"}" "$DEPLOYMENT_REGISTRY" > "${DEPLOYMENT_REGISTRY}.tmp"
        else
            yq eval ".deployments.\"$deployment_id\" = {\"app_name\": \"$app_name\", \"state_dir\": \"$state_dir\", \"vm_ip\": \"$vm_ip\", \"created_at\": \"$timestamp\", \"status\": \"active\"}" "$DEPLOYMENT_REGISTRY" > "${DEPLOYMENT_REGISTRY}.tmp"
        fi
        mv "${DEPLOYMENT_REGISTRY}.tmp" "$DEPLOYMENT_REGISTRY"
    else
        # Fallback for systems without yq
        echo "Warning: yq not available, using basic YAML registry" >&2
        # For now, create a simple text-based registry
        if [ -n "$contract_id" ]; then
            echo "$deployment_id|$app_name|$state_dir|$vm_ip|$contract_id|$timestamp|active" >> "${DEPLOYMENT_REGISTRY}.tmp"
        else
            echo "$deployment_id|$app_name|$state_dir|$vm_ip|||$timestamp|active" >> "${DEPLOYMENT_REGISTRY}.tmp"
        fi
        if [ ! -f "${DEPLOYMENT_REGISTRY}.backup" ]; then
            cp "$DEPLOYMENT_REGISTRY" "${DEPLOYMENT_REGISTRY}.backup" 2>/dev/null || true
        fi
        mv "${DEPLOYMENT_REGISTRY}.tmp" "$DEPLOYMENT_REGISTRY"
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
        # Use yq to extract deployment with better error handling
        local result=$(yq eval ".deployments.\"$deployment_id\" // null" "$DEPLOYMENT_REGISTRY" 2>/dev/null || echo "null")
        if [ "$result" != "null" ] && [ -n "$result" ] && [ "$result" != "" ]; then
            echo "$result"
        fi
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

# Get all deployments (simplified for basic functionality)
get_all_deployments() {
    init_deployment_registry
    
    if command_exists yq; then
        # Use a simpler yq expression to avoid syntax errors
        yq eval '.deployments | keys[]' "$DEPLOYMENT_REGISTRY" | while read -r deployment_id; do
            if [ -n "$deployment_id" ]; then
                local app_name=$(yq eval ".deployments.\"$deployment_id\".app_name // \"\"" "$DEPLOYMENT_REGISTRY")
                local vm_ip=$(yq eval ".deployments.\"$deployment_id\".vm_ip // \"\"" "$DEPLOYMENT_REGISTRY")
                local contract_id=$(yq eval ".deployments.\"$deployment_id\".contract_id // \"\"" "$DEPLOYMENT_REGISTRY")
                local status=$(yq eval ".deployments.\"$deployment_id\".status // \"\"" "$DEPLOYMENT_REGISTRY")
                local created_at=$(yq eval ".deployments.\"$deployment_id\".created_at // \"\"" "$DEPLOYMENT_REGISTRY")
                echo "$deployment_id|$app_name|$vm_ip|$contract_id|$status|$created_at"
            fi
        done
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

# Helper function to calculate deployment age
calculate_deployment_age() {
    local created_at="$1"
    
    if [ -z "$created_at" ]; then
        echo "unknown"
        return
    fi
    
    # Handle "null" or empty values from registry
    if [ "$created_at" = "null" ] || [ "$created_at" = "" ]; then
        echo "unknown"
        return
    fi
    
    # Parse ISO 8601 timestamp with better error handling
    local created_timestamp
    if [[ "$created_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
        created_timestamp=$(date -d "$created_at" +%s 2>/dev/null || echo 0)
    else
        # Try to parse as Unix timestamp
        created_timestamp=$(date -d "@$created_at" +%s 2>/dev/null || echo 0)
    fi
    
    local current_timestamp=$(date -u +%s)
    
    if [ "$created_timestamp" -eq 0 ]; then
        echo "unknown"
        return
    fi
    
    local age_seconds=$((current_timestamp - created_timestamp))
    
    if [ $age_seconds -lt 0 ]; then
        echo "just now"
    elif [ $age_seconds -lt 60 ]; then
        echo "${age_seconds}s ago"
    elif [ $age_seconds -lt 3600 ]; then
        echo "$((age_seconds / 60))m ago"
    elif [ $age_seconds -lt 86400 ]; then
        echo "$((age_seconds / 3600))h ago"
    elif [ $age_seconds -lt 2592000 ]; then
        echo "$((age_seconds / 86400))d ago"
    else
        echo "$((age_seconds / 2592000))mo ago"
    fi
}

# Resolve partial deployment ID (Docker-style)
resolve_partial_deployment_id() {
    local partial_id="$1"
    local max_matches="${2:-10}"
    
    init_deployment_registry
    
    local matches=()
    
    if command_exists yq; then
        # Get all deployment IDs that start with partial_id
        local all_deployments=$(yq eval '.deployments | keys | .[]' "$DEPLOYMENT_REGISTRY" 2>/dev/null || echo "")
        
        while IFS= read -r deployment_id; do
            if [[ "$deployment_id" == "$partial_id"* ]]; then
                matches+=("$deployment_id")
            fi
        done <<< "$all_deployments"
    else
        # Fallback: search in text registry
        while IFS='|' read -r deployment_id app_name state_dir vm_ip timestamp status; do
            if [[ "$deployment_id" == "$partial_id"* ]]; then
                matches+=("$deployment_id")
            fi
        done < "$DEPLOYMENT_REGISTRY"
    fi
    
    # Return matches based on count
    case ${#matches[@]} in
        0)
            return 1  # No matches
            ;;
        1)
            echo "${matches[0]}"
            return 0  # Single match - unique
            ;;
        *)
            # Multiple matches - show them for user selection
            printf '%s\n' "${matches[@]}"
            return 2  # Multiple matches - need user choice
            ;;
    esac
}

# Resolve deployment identifier (ID or app name) with smart matching
resolve_deployment() {
    local identifier="$1"
    
    # If it looks like a deployment ID, try exact match first
    if is_deployment_id "$identifier"; then
        local deployment_id="$identifier"
        if [ -n "$(get_deployment_by_id "$deployment_id")" ]; then
            echo "$deployment_id"
            return 0
        fi
    fi
    
    # Try partial ID resolution
    local partial_result=$(resolve_partial_deployment_id "$identifier" 2>/dev/null)
    local resolve_result=$?
    
    case $resolve_result in
        0)
            # Single partial match found
            echo "$partial_result"
            return 0
            ;;
        2)
            # Multiple partial matches - show selection menu
            echo "AMBIGUOUS:$partial_result"
            return 3
            ;;
    esac
    
    # Otherwise, search for active deployment with this app name
    local deployment_id=$(get_active_deployment_for_app "$identifier")
    if [ -n "$deployment_id" ]; then
        echo "$deployment_id"
        return 0
    fi
    
    return 1
}

# List deployments in Docker-style format with contract linkage (auto-filtered)
list_deployments_docker_style() {
    echo "Deployments (Docker-style):"
    echo ""
    
    local deployments=$(get_all_deployments)
    if [ -z "$deployments" ]; then
        echo "(no deployments found)"
        return 0
    fi
    
    # Filter to show only deployments with VALID contract IDs (must exist on grid)
    local valid_deployments=""
    if command_exists yq; then
        valid_deployments=$(echo "$deployments" | while IFS='|' read -r deployment_id app_name vm_ip contract_id status created_at; do
            # Check both existence AND validity against grid
            if [ -n "$contract_id" ] && [ "$contract_id" != "null" ]; then
                # Validate contract exists on grid
                if [ "$(validate_deployment_contracts "$deployment_id" 2>/dev/null)" = "true" ]; then
                    echo "$deployment_id|$app_name|$vm_ip|$contract_id|$status|$created_at"
                fi
            fi
        done)
    else
        valid_deployments=$(echo "$deployments" | while IFS='|' read -r deployment_id app_name vm_ip contract_id status created_at; do
            # Check both existence AND validity against grid
            if [ -n "$contract_id" ] && [ "$contract_id" != "null" ]; then
                # Validate contract exists on grid
                if [ "$(validate_deployment_contracts "$deployment_id" 2>/dev/null)" = "true" ]; then
                    echo "$deployment_id|$app_name|$vm_ip|$contract_id|$status|$created_at"
                fi
            fi
        done)
    fi
    
    # Show header only if there are valid deployments
    if [ -z "$valid_deployments" ]; then
        echo "(no active deployments with contracts)"
        return 0
    fi
    
    echo "CONTAINER ID    APP NAME           STATUS    IP ADDRESS    CONTRACT    AGE"
    echo "───────────────────────────────────────────────────────────────────────────"
    
    # Display filtered deployments
    echo "$valid_deployments" | while IFS='|' read -r deployment_id app_name vm_ip contract_id status created_at; do
        local age=$(calculate_deployment_age "$created_at")
        
        printf "%-16s %-19s %-9s %-12s %-9s %s\n" "$deployment_id" "$app_name" "$status" "${vm_ip:-N/A}" "$contract_id" "$age"
    done
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
export -f resolve_partial_deployment_id
export -f calculate_deployment_age
export -f list_deployments_docker_style

# Clean up invalid deployments from registry and mark as failed
cleanup_invalid_deployments() {
    local deployments=$(get_all_deployments 2>/dev/null || echo "")
    
    if [ -z "$deployments" ]; then
        return 0
    fi
    
    # Check if we have tfcmd for contract validation
    local has_tfcmd=false
    if command -v tfcmd >/dev/null 2>&1; then
        has_tfcmd=true
    fi
    
    if [ "$has_tfcmd" = false ]; then
        return 0  # Can't validate without tfcmd
    fi
    
    # Load credentials for contract validation
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/../login.sh" ]; then
        source "$script_dir/../login.sh" 2>/dev/null
        if load_credentials 2>/dev/null; then
            local failed_count=0
            
            if command_exists yq; then
                while IFS='|' read -r deployment_id app_name vm_ip status created_at; do
                    if [ -n "$deployment_id" ]; then
                        local state_dir="$HOME/.config/tfgrid-compose/state/$deployment_id"
                        if [ -d "$state_dir" ]; then
                            # Check if this deployment has valid contracts
                            local deployment_name=$(grep "^deployment_name:" "$state_dir/state.yaml" 2>/dev/null | awk '{print $2}' || echo "vm")
                            
                            # Check if this specific deployment has active contracts
                            if ! echo "$TFGRID_MNEMONIC" 2>/dev/null | tfcmd get contracts 2>/dev/null | grep -q "$deployment_name"; then
                                # Mark as failed instead of removing
                                log_info "Marking deployment as failed (contracts cancelled): $deployment_id"
                                update_deployment_status "$deployment_id" "failed"
                                ((failed_count++))
                            fi
                        fi
                    fi
                done <<< "$deployments"
                
                if [ $failed_count -gt 0 ]; then
                    log_info "Marked $failed_count deployment(s) as failed (contracts cancelled)"
                fi
            fi
        fi
    fi
}

export -f cleanup_invalid_deployments

# Clean up orphaned deployments (registry entries without corresponding grid contracts)
cleanup_orphaned_deployments() {
    local deployments=$(get_all_deployments_raw 2>/dev/null || echo "")
    
    if [ -z "$deployments" ]; then
        return 0
    fi
    
    # Check if we have tfcmd for contract validation
    local has_tfcmd=false
    if command -v tfcmd >/dev/null 2>&1; then
        has_tfcmd=true
    fi
    
    if [ "$has_tfcmd" = false ]; then
        return 0  # Can't validate without tfcmd
    fi
    
    # Load credentials for contract validation
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$script_dir/../login.sh" ]; then
        source "$script_dir/../login.sh" 2>/dev/null
        if load_credentials 2>/dev/null; then
            local cleaned_count=0
            
            if command_exists yq; then
                while IFS='|' read -r deployment_id app_name vm_ip contract_id status created_at; do
                    if [ -n "$deployment_id" ] && [ -n "$contract_id" ]; then
                        # Check if this contract exists on the grid
                        local contract_exists="false"
                        
                        # Query tfgrid-compose contracts to get active contracts
                        local contracts_output=$(tfgrid-compose contracts list 2>/dev/null || echo "")
                        
                        if echo "$contracts_output" | grep -q "$contract_id"; then
                            contract_exists="true"
                        fi
                        
                        if [ "$contract_exists" = "false" ]; then
                            log_info "Removing orphaned deployment: $deployment_id (contract $contract_id not found on grid)"
                            unregister_deployment "$deployment_id"
                            ((cleaned_count++))
                        fi
                    elif [ -n "$deployment_id" ] && [ -z "$contract_id" ]; then
                        # Registry entry without contract ID - likely old format, remove it
                        log_info "Removing legacy deployment without contract ID: $deployment_id"
                        unregister_deployment "$deployment_id"
                        ((cleaned_count++))
                    fi
                done <<< "$deployments"
                
                if [ $cleaned_count -gt 0 ]; then
                    log_info "Cleaned up $cleaned_count orphaned deployment(s)"
                fi
            fi
        fi
    fi
}

# Get raw deployments without cleanup (for internal use)
get_all_deployments_raw() {
    init_deployment_registry
    
    if command_exists yq; then
        # Use a simpler yq expression to avoid syntax errors
        yq eval '.deployments | keys[]' "$DEPLOYMENT_REGISTRY" | while read -r deployment_id; do
            if [ -n "$deployment_id" ]; then
                local app_name=$(yq eval ".deployments.\"$deployment_id\".app_name // \"\"" "$DEPLOYMENT_REGISTRY")
                local vm_ip=$(yq eval ".deployments.\"$deployment_id\".vm_ip // \"\"" "$DEPLOYMENT_REGISTRY")
                local contract_id=$(yq eval ".deployments.\"$deployment_id\".contract_id // \"\"" "$DEPLOYMENT_REGISTRY")
                local status=$(yq eval ".deployments.\"$deployment_id\".status // \"\"" "$DEPLOYMENT_REGISTRY")
                local created_at=$(yq eval ".deployments.\"$deployment_id\".created_at // \"\"" "$DEPLOYMENT_REGISTRY")
                echo "$deployment_id|$app_name|$vm_ip|$contract_id|$status|$created_at"
            fi
        done
    else
        # Fallback: show text registry
        cat "$DEPLOYMENT_REGISTRY" 2>/dev/null || echo ""
    fi
}

export -f cleanup_orphaned_deployments
export -f get_all_deployments_raw

# Initialize on source
if [ -z "$DEPLOYMENT_ID_INITIALIZED" ]; then
    init_deployment_registry
    DEPLOYMENT_ID_INITIALIZED=1
fi