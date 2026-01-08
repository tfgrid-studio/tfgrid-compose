#!/bin/bash
# Deployment Status Management System
# Tracks and manages deployment health and status

set -e

# Deployment status directory
DEPLOYMENTS_DIR="$HOME/.config/tfgrid-compose/deployments"

# Initialize deployment status tracking
init_deployment_status() {
    mkdir -p "$DEPLOYMENTS_DIR"
    mkdir -p "$DEPLOYMENTS_DIR/logs"
}

# Record deployment status
# Usage: record_deployment_status "deployment-name" "active|failed|deploying|unknown"
record_deployment_status() {
    local deployment_name="$1"
    local status="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local status_file="$DEPLOYMENTS_DIR/$deployment_name.status"
    
    # Create status record
    cat > "$status_file" << EOF
{
  "status": "$status",
  "timestamp": "$timestamp",
  "last_check": "$timestamp"
}
EOF
    
    log_debug "Recorded status '$status' for deployment '$deployment_name'"
}

# Update deployment last_check timestamp
update_deployment_check() {
    local deployment_name="$1"
    local status_file="$DEPLOYMENTS_DIR/$deployment_name.status"
    
    if [ -f "$status_file" ]; then
        local current_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        # Update only the last_check field while preserving status
        local current_status=$(jq -r '.status' "$status_file")
        cat > "$status_file" << EOF
{
  "status": "$current_status",
  "timestamp": "$(jq -r '.timestamp' "$status_file")",
  "last_check": "$current_timestamp"
}
EOF
    fi
}

# Check deployment status with contract validation
# Returns: status or "unknown" if not found
check_deployment_status() {
    local deployment_name="$1"
    local status_file="$DEPLOYMENTS_DIR/$deployment_name.status"
    
    if [ ! -f "$status_file" ]; then
        # Check if this deployment exists in registry but has no status file
        local registry_status=$(get_deployment_status_from_registry "$deployment_name" 2>/dev/null || echo "")
        if [ -n "$registry_status" ]; then
            echo "$registry_status"
            return 0
        fi
        echo "unknown"
        return 1
    fi
    
    local status=$(jq -r '.status' "$status_file")
    
    # Validate status against actual contracts if tfcmd is available
    local has_tfcmd=false
    if command -v tfcmd >/dev/null 2>&1; then
        has_tfcmd=true
    fi
    
    if [ "$has_tfcmd" = true ]; then
        # Validate contract status
        local contract_valid=$(validate_deployment_contracts "$deployment_name")
        if [ "$contract_valid" = "false" ]; then
            # Contracts are invalid, update status to failed
            mark_deployment_failed "$deployment_name" "Contracts cancelled"
            echo "failed"
            return 0
        fi
    fi
    
    echo "$status"
}

# Get deployment status from registry (Docker-style compatible)
get_deployment_status_from_registry() {
    local deployment_id="$1"
    
    # Try to get status from deployment registry
    local deployment_details=$(get_deployment_by_id "$deployment_id" 2>/dev/null || echo "")
    if [ -n "$deployment_details" ]; then
        # Extract status from YAML-like output
        echo "$deployment_details" | grep -E "^\s*status:" | awk '{print $2}' | tr -d '"' || echo "active"
    else
        echo ""
    fi
}

# Validate deployment contracts on the grid
validate_deployment_contracts() {
    local deployment_id="$1"

    # Check if tfcmd is available first
    if ! command -v tfcmd >/dev/null 2>&1; then
        echo "true"  # Assume valid if tfcmd not installed (don't filter out deployments)
        return
    fi

    # Load credentials with timeout
    if [ ! -f "$SCRIPT_DIR/login.sh" ]; then
        echo "true"  # Can't validate, but don't invalidate deployments
        return
    fi

    # Timeout credential loading to prevent hanging
    local credentials_loaded=false
    if timeout 10 bash -c "source '$SCRIPT_DIR/login.sh' 2>/dev/null && load_credentials 2>/dev/null" >/dev/null 2>&1; then
        credentials_loaded=true
    fi

    if [ "$credentials_loaded" != "true" ]; then
        echo "true"  # Can't validate credentials, assume valid
        return
    fi

    # Get actual contracts from tfcmd with timeout
    local contracts_output=""
    if timeout 15 bash -c "tfcmd get contracts 2>/dev/null" 2>/dev/null; then
        contracts_output=$(timeout 15 bash -c "tfcmd get contracts 2>/dev/null" 2>/dev/null || echo "")
    else
        echo "true"  # Timeout, assume valid
        return
    fi

    # If no contracts found, validation unclear - assume valid
    if [ -z "$contracts_output" ]; then
        echo "true"  # No contracts returned, don't invalidate
        return
    fi

    # Get expected contract ID from deployment registry
    local deployment_details=$(get_deployment_by_id "$deployment_id" 2>/dev/null || echo "")
    local expected_contract_id=$(echo "$deployment_details" | grep -E "^\s*contract_id:" | awk '{print $2}' | tr -d '"' || echo "")

    # If no contract ID expected, this is an orphaned deployment
    if [ -z "$expected_contract_id" ] || [ "$expected_contract_id" = "null" ]; then
        echo "false"  # Invalid - no contract ID
        return
    fi

    # Check if the expected contract ID exists in the contracts list
    # Format: "1632034    8          vm         vm              vm/vm"
    # Contract ID is at the start of the line
    if echo "$contracts_output" | grep -qE "^${expected_contract_id}[[:space:]]"; then
        echo "true"  # Contract found and active
    else
        echo "false" # Contract not found or cancelled
    fi
}

# Get deployment status with details
get_deployment_status_details() {
    local deployment_name="$1"
    local status_file="$DEPLOYMENTS_DIR/$deployment_name.status"
    
    if [ ! -f "$status_file" ]; then
        echo "Deployment not found"
        return 1
    fi
    
    cat "$status_file"
}

# Get active deployments for context selection
# Filters deployments by status, excluding failed ones
get_active_deployments() {
    local pattern="${1:-*}"
    
    for status_file in "$DEPLOYMENTS_DIR"/$pattern.status; do
        if [ -f "$status_file" ]; then
            local name=$(basename "$status_file" .status)
            local status=$(jq -r '.status' "$status_file")
            
            # Include only active deployments
            if [ "$status" = "active" ]; then
                echo "$name"
            fi
        fi
    done
}

# Get all deployments with their status
get_all_deployments() {
    local pattern="${1:-*}"
    
    for status_file in "$DEPLOYMENTS_DIR"/$pattern.status; do
        if [ -f "$status_file" ]; then
            local name=$(basename "$status_file" .status)
            local status=$(jq -r '.status' "$status_file")
            local timestamp=$(jq -r '.timestamp' "$status_file")
            local last_check=$(jq -r '.last_check' "$status_file")
            
            echo "$name|$status|$timestamp|$last_check"
        fi
    done
}

# Log deployment error
log_deployment_error() {
    local deployment_name="$1"
    local error_message="$2"
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")
    local log_file="$DEPLOYMENTS_DIR/logs/${deployment_name}.log"
    
    echo "[$timestamp] ERROR: $error_message" >> "$log_file"
}

# Log deployment info
log_deployment_info() {
    local deployment_name="$1"
    local message="$2"
    local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")
    local log_file="$DEPLOYMENTS_DIR/logs/${deployment_name}.log"
    
    echo "[$timestamp] INFO: $message" >> "$log_file"
}

# Get deployment logs
get_deployment_logs() {
    local deployment_name="$1"
    local log_file="$DEPLOYMENTS_DIR/logs/${deployment_name}.log"
    
    if [ -f "$log_file" ]; then
        cat "$log_file"
    else
        echo "No logs found for deployment '$deployment_name'"
    fi
}

# Clear deployment logs
clear_deployment_logs() {
    local deployment_name="$1"
    local log_file="$DEPLOYMENTS_DIR/logs/${deployment_name}.log"
    
    if [ -f "$log_file" ]; then
        rm "$log_file"
        echo "Cleared logs for deployment '$deployment_name'"
    else
        echo "No logs found for deployment '$deployment_name'"
    fi
}

# Reset deployment status (useful for retry)
reset_deployment_status() {
    local deployment_name="$1"
    local status_file="$DEPLOYMENTS_DIR/$deployment_name.status"
    
    if [ -f "$status_file" ]; then
        rm "$status_file"
        log_info "Reset status for deployment '$deployment_name'"
    fi
}

# Validate deployment for context inclusion
# Returns 0 if deployment is healthy and should be included in context selection
validate_deployment_for_context() {
    local deployment_name="$1"
    
    # First check if this is a Docker-style deployment with a valid contract
    local deployment_details=$(get_deployment_by_id "$deployment_name" 2>/dev/null || echo "")
    if [ -n "$deployment_details" ]; then
        local contract_id=$(echo "$deployment_details" | grep -E "^\s*contract_id:" | awk '{print $2}' | tr -d '"' || echo "")
        local app_name=$(echo "$deployment_details" | grep -E "^\s*app_name:" | awk '{print $2}' | tr -d '"' || echo "")
        local status=$(echo "$deployment_details" | grep -E "^\s*status:" | awk '{print $2}' | tr -d '"' || echo "active")
        local ipv4_address=$(echo "$deployment_details" | grep -E "^\s*ipv4_address:" | awk '{print $2}' | tr -d '"' || echo "")
        
        log_debug "Validating Docker-style deployment '$deployment_name':"
        log_debug "  App: $app_name"
        log_debug "  Status: $status"
        log_debug "  Contract: $contract_id"
        log_debug "  VM IP: $ipv4_address"
        
        # If deployment has a contract ID, it's valid regardless of status
        if [ -n "$contract_id" ]; then
            log_debug "Docker-style deployment '$deployment_name' ($app_name) has contract $contract_id, including in context"
            return 0  # Include Docker-style deployments with contracts
        elif [ -n "$ipv4_address" ] && [ "$status" != "failed" ]; then
            # Include deployments with VM IP and non-failed status (legacy deployments)
            log_debug "Including legacy deployment '$deployment_name' with VM IP: $ipv4_address"
            return 0
        fi
    fi
    
    # Fallback to status-based validation for non-Docker deployments
    local status=$(check_deployment_status "$deployment_name")
    
    log_debug "Fallback status validation for '$deployment_name': $status"
    
    case "$status" in
        "active")
            return 0  # Include in context selection
            ;;
        "failed")
            log_debug "Deployment '$deployment_name' is failed, excluding from context selection"
            return 1  # Exclude from context selection
            ;;
        "deploying")
            log_debug "Deployment '$deployment_name' is still deploying, excluding from context selection"
            return 1  # Exclude from context selection
            ;;
        "unknown")
            log_debug "Deployment '$deployment_name' status unknown, including in context selection"
            return 0  # Include (will be validated later)
            ;;
        *)
            log_debug "Deployment '$deployment_name' has unrecognized status '$status', including in context selection"
            return 0  # Include as fallback
            ;;
    esac
}

# Mark deployment as deploying (when up command starts)
mark_deployment_deploying() {
    local deployment_name="$1"
    record_deployment_status "$deployment_name" "deploying"
    log_deployment_info "$deployment_name" "Deployment started"
}

# Mark deployment as active (when up command succeeds)
mark_deployment_active() {
    local deployment_name="$1"
    record_deployment_status "$deployment_name" "active"
    log_deployment_info "$deployment_name" "Deployment completed successfully"
}

# Mark deployment as failed (when up command fails)
mark_deployment_failed() {
    local deployment_name="$1"
    local error_message="${2:-Unknown error}"
    record_deployment_status "$deployment_name" "failed"
    log_deployment_error "$deployment_name" "$error_message"
    log_info "Deployment '$deployment_name' marked as failed"
}

# Cleanup deployment (when down command runs)
cleanup_deployment() {
    local deployment_name="$1"
    local status_file="$DEPLOYMENTS_DIR/$deployment_name.status"
    local log_file="$DEPLOYMENTS_DIR/logs/${deployment_name}.log"
    
    # Remove status file
    [ -f "$status_file" ] && rm "$status_file"
    
    # Remove logs
    [ -f "$log_file" ] && rm "$log_file"
    
    log_info "Cleaned up deployment '$deployment_name'"
}

# Get deployment statistics
get_deployment_stats() {
    local total=0
    local active=0
    local failed=0
    local deploying=0
    local unknown=0
    
    while IFS='|' read -r name status timestamp last_check; do
        total=$((total + 1))
        case "$status" in
            "active") active=$((active + 1)) ;;
            "failed") failed=$((failed + 1)) ;;
            "deploying") deploying=$((deploying + 1)) ;;
            *) unknown=$((unknown + 1)) ;;
        esac
    done < <(get_all_deployments)
    
    echo "Total: $total, Active: $active, Failed: $failed, Deploying: $deploying, Unknown: $unknown"
}

# Health check wrapper - to be called by orchestrator
perform_deployment_health_check() {
    local deployment_name="$1"
    local deployment_type="${2:-generic}"
    
    # Update last check timestamp
    update_deployment_check "$deployment_name"
    
    # Perform health check based on deployment type
    case "$deployment_type" in
        "tfgrid-ai-stack"|"ai-stack")
            health_check_ai_stack "$deployment_name"
            ;;
        "tfgrid-ai-agent"|"ai-agent")
            health_check_ai_agent "$deployment_name"
            ;;
        *)
            health_check_generic "$deployment_name"
            ;;
    esac
    
    local health_result=$?
    
    if [ $health_result -eq 0 ]; then
        # Deployment is healthy
        if [ "$(check_deployment_status "$deployment_name")" != "active" ]; then
            mark_deployment_active "$deployment_name"
        fi
        return 0
    else
        # Deployment is unhealthy
        if [ "$(check_deployment_status "$deployment_name")" != "failed" ]; then
            mark_deployment_failed "$deployment_name" "Health check failed"
        fi
        return 1
    fi
}

# AI Stack specific health check
health_check_ai_stack() {
    local deployment_name="$1"
    
    # Load deployment state to get IPs
    local state_file="$HOME/.config/tfgrid-compose/state/$deployment_name/state.yaml"
    if [ ! -f "$state_file" ]; then
        log_debug "State file not found for $deployment_name"
        return 1
    fi
    
    # Extract IPs from state
    local gateway_ip=$(grep "^gateway_ip:" "$state_file" 2>/dev/null | awk '{print $2}' || echo "")
    local ai_agent_ip=$(grep "^ai_agent_ip:" "$state_file" 2>/dev/null | awk '{print $2}' || echo "")
    local gitea_ip=$(grep "^gitea_ip:" "$state_file" 2>/dev/null | awk '{print $2}' || echo "")
    
    log_debug "Health checking AI Stack deployment $deployment_name:"
    log_debug "  Gateway: $gateway_ip"
    log_debug "  AI Agent: $ai_agent_ip" 
    log_debug "  Gitea: $gitea_ip"
    
    local health_status=0
    
    # Check Gateway API health
    if [ -n "$gateway_ip" ]; then
        if curl -sf --max-time 10 "http://$gateway_ip/api/v1/health" >/dev/null 2>&1; then
            log_debug "  ✅ Gateway API healthy"
        else
            log_debug "  ❌ Gateway API unhealthy"
            health_status=1
        fi
    else
        log_debug "  ❌ Gateway IP not found"
        health_status=1
    fi
    
    # Check AI Agent API health
    if [ -n "$ai_agent_ip" ]; then
        if curl -sf --max-time 10 "http://$ai_agent_ip/health" >/dev/null 2>&1; then
            log_debug "  ✅ AI Agent API healthy"
        else
            log_debug "  ❌ AI Agent API unhealthy"
            health_status=1
        fi
    else
        log_debug "  ❌ AI Agent IP not found"
        health_status=1
    fi
    
    # Check Gitea health
    if [ -n "$gitea_ip" ]; then
        if curl -sf --max-time 10 "http://$gitea_ip:3000" >/dev/null 2>&1; then
            log_debug "  ✅ Gitea healthy"
        else
            log_debug "  ❌ Gitea unhealthy"
            health_status=1
        fi
    else
        log_debug "  ❌ Gitea IP not found"
        health_status=1
    fi
    
    return $health_status
}

# AI Agent specific health check
health_check_ai_agent() {
    local deployment_name="$1"
    
    # Load deployment state
    local state_file="$HOME/.config/tfgrid-compose/state/$deployment_name/state.yaml"
    if [ ! -f "$state_file" ]; then
        return 1
    fi
    
    local ipv4_address=$(grep "^ipv4_address:" "$state_file" 2>/dev/null | awk '{print $2}' || echo "")
    
    if [ -z "$ipv4_address" ]; then
        return 1
    fi
    
    # Check if AI agent service is responding
    if curl -sf --max-time 10 "http://$ipv4_address:8000/health" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Generic health check for unknown deployment types
health_check_generic() {
    local deployment_name="$1"
    
    # Load deployment state
    local state_file="$HOME/.config/tfgrid-compose/state/$deployment_name/state.yaml"
    if [ ! -f "$state_file" ]; then
        return 1
    fi
    
    local ipv4_address=$(grep "^ipv4_address:" "$state_file" 2>/dev/null | awk '{print $2}' || echo "")
    
    if [ -z "$ipv4_address" ]; then
        return 1
    fi
    
    # Basic connectivity check - try SSH port
    if timeout 5 bash -c "echo >/dev/tcp/$ipv4_address/22" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Initialize on source
if [ -z "$DEPLOYMENT_STATUS_INITIALIZED" ]; then
    init_deployment_status
    DEPLOYMENT_STATUS_INITIALIZED=1
fi
