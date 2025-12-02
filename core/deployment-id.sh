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

    # Validate inputs
    if [ -z "$deployment_id" ] || [ -z "$app_name" ] || [ -z "$vm_ip" ]; then
        log_error "register_deployment: missing required parameters"
        return 1
    fi

    # Best-effort lookup of mycelium_ip from state.yaml (for registry convenience)
    local mycelium_ip=""
    if [ -n "$state_dir" ] && [ -f "$state_dir/state.yaml" ]; then
        mycelium_ip=$(grep "^mycelium_ip:" "$state_dir/state.yaml" 2>/dev/null | head -n1 | awk '{print $2}' || echo "")
    fi

    local origin="${APP_ORIGIN:-}"

    if [ -z "$origin" ] && [ -n "$state_dir" ] && [ -f "$state_dir/state.yaml" ]; then
        local app_dir=""
        app_dir=$(grep "^app_dir:" "$state_dir/state.yaml" 2>/dev/null | head -n1 | awk '{print $2}' || echo "")
        if [ -n "$app_dir" ] && [ -n "${APPS_CACHE_DIR:-}" ]; then
            case "$app_dir" in
                "$APPS_CACHE_DIR"/*)
                    origin="registry"
                    ;;
                *)
                    origin="custom"
                    ;;
            esac
        fi
    fi

    # Validate deployment ID format (16 hex chars)
    if ! [[ "$deployment_id" =~ ^[a-f0-9]{16}$ ]]; then
        log_error "register_deployment: invalid deployment ID format: $deployment_id"
        return 1
    fi

    # Validate contract ID format if provided
    if [ -n "$contract_id" ] && ! [[ "$contract_id" =~ ^[0-9]+$ ]]; then
        log_error "register_deployment: invalid contract ID format: $contract_id"
        return 1
    fi

    init_deployment_registry

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Use yq if available, otherwise use simple sed/awk
    if command_exists yq; then
        # Construct the JSON object safely (include mycelium_ip when available)
        local json_obj="{\"app_name\": \"$app_name\", \"state_dir\": \"$state_dir\", \"vm_ip\": \"$vm_ip\", \"mycelium_ip\": \"$mycelium_ip\", \"created_at\": \"$timestamp\", \"status\": \"active\"}"

        if [ -n "$origin" ]; then
            json_obj=$(echo "$json_obj" | sed 's/}$/, "origin": "'$origin'"}/')
        fi

        if [ -n "$contract_id" ]; then
            json_obj=$(echo "$json_obj" | sed 's/}$/, "contract_id": "'$contract_id'"}/')
        fi

        # Set the deployment entry
        if yq eval ".deployments.\"$deployment_id\" = $json_obj" "$DEPLOYMENT_REGISTRY" > "${DEPLOYMENT_REGISTRY}.tmp" 2>/dev/null; then
            mv "${DEPLOYMENT_REGISTRY}.tmp" "$DEPLOYMENT_REGISTRY"
            log_info "Registered deployment: $deployment_id ($app_name)"
        else
            rm -f "${DEPLOYMENT_REGISTRY}.tmp"
            log_error "Failed to register deployment: $deployment_id"
            return 1
        fi
    else
        # Fallback for systems without yq
        log_warning "yq not available, using basic text registry"
        local line=""
        if [ -n "$contract_id" ]; then
            line="$deployment_id|$app_name|$state_dir|$vm_ip|$contract_id|$timestamp|active"
        else
            line="$deployment_id|$app_name|$state_dir|$vm_ip||$timestamp|active"
        fi
        echo "$line" >> "$DEPLOYMENT_REGISTRY"
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

# Get active deployment for app name (returns most recent)
get_active_deployment_for_app() {
    local app_name="$1"
    
    init_deployment_registry
    
    if command_exists yq; then
        # Get deployments for this app, sort by created_at descending, and return the first (most recent)
        yq eval ".deployments | to_entries | .[] | select(.value.app_name == \"$app_name\" and .value.status == \"active\") | select(.value.created_at != null) | .key" "$DEPLOYMENT_REGISTRY" | while read -r key; do
            local created_at=$(yq eval ".deployments.\"$key\".created_at" "$DEPLOYMENT_REGISTRY" 2>/dev/null)
            if [ "$created_at" != "null" ] && [ -n "$created_at" ]; then
                echo "$key|$created_at"
            fi
        done | sort -t'|' -k2 -r | head -1 | cut -d'|' -f1
    else
        # Fallback: search in text registry, use tail to get most recent
        local line=$(grep "|$app_name|.*|.*|active$" "$DEPLOYMENT_REGISTRY" 2>/dev/null | tail -1 || echo "")
        if [ -n "$line" ]; then
            echo "$line" | cut -d'|' -f1
        fi
    fi
}

# Get all deployments (simplified for basic functionality)
get_all_deployments() {
	init_deployment_registry

	# Always use a YAML/text parser to avoid yq version/syntax differences
	# If registry is plain text (legacy format), just cat it
	if ! grep -q "^deployments:" "$DEPLOYMENT_REGISTRY" 2>/dev/null; then
		cat "$DEPLOYMENT_REGISTRY" 2>/dev/null || echo ""
		return 0
	fi

	# Minimal YAML parser for deployments: { id: {app_name, vm_ip, contract_id, status, created_at, origin} }
	local id="" app_name="" vm_ip="" contract_id="" status="" created_at="" origin="" in_vm_ip_block=false

	while IFS= read -r line; do
		# Detect new deployment block: two-space indented 16-hex key ending with ':'
		if [[ "$line" =~ ^[[:space:]]{2}([a-f0-9]{16}):[[:space:]]*$ ]]; then
			# Flush previous record if any
			if [ -n "$id" ]; then
				echo "$id|$app_name|$vm_ip|$contract_id|$status|$created_at|$origin"
			fi

			id="${BASH_REMATCH[1]}"
			app_name="" vm_ip="" contract_id="" status="" created_at="" origin=""
			in_vm_ip_block=false
			continue
		fi

		# Inside a deployment block, parse simple key: value pairs
		if [ -n "$id" ]; then
			# vm_ip scalar or block start
			if [[ "$line" =~ ^[[:space:]]{4}vm_ip:[[:space:]]*(.*)$ ]]; then
				local rhs="${BASH_REMATCH[1]}"
				in_vm_ip_block=false
				# Handle simple scalar on same line
				if [ -n "$rhs" ] && [ "$rhs" != "|-" ]; then
					vm_ip="${rhs//\"/}"
				elif [ "$rhs" = "|-" ]; then
					# Start of multiline block, capture next non-empty scalar line
					in_vm_ip_block=true
				fi
				continue
			fi

			# Capture first non-empty line of vm_ip block
			if [ "$in_vm_ip_block" = true ]; then
				if [[ "$line" =~ ^[[:space:]]{6}([0-9.]+).* ]]; then
					vm_ip="${BASH_REMATCH[1]}"
					in_vm_ip_block=false
				fi
				continue
			fi

			# Other scalar fields
			if [[ "$line" =~ ^[[:space:]]{4}app_name:[[:space:]]*(.*)$ ]]; then
				app_name="${BASH_REMATCH[1]//\"/}"
				continue
			fi
			if [[ "$line" =~ ^[[:space:]]{4}contract_id:[[:space:]]*(.*)$ ]]; then
				contract_id="${BASH_REMATCH[1]//\"/}"
				continue
			fi
			if [[ "$line" =~ ^[[:space:]]{4}status:[[:space:]]*(.*)$ ]]; then
				status="${BASH_REMATCH[1]//\"/}"
				continue
			fi
			if [[ "$line" =~ ^[[:space:]]{4}created_at:[[:space:]]*(.*)$ ]]; then
				created_at="${BASH_REMATCH[1]//\"/}"
				continue
			fi
			if [[ "$line" =~ ^[[:space:]]{4}origin:[[:space:]]*(.*)$ ]]; then
				origin="${BASH_REMATCH[1]//\"/}"
				continue
			fi
		fi
	done < "$DEPLOYMENT_REGISTRY"

	# Flush last record
	if [ -n "$id" ]; then
		echo "$id|$app_name|$vm_ip|$contract_id|$status|$created_at|$origin"
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
    
    # Check if it looks like an app name (contains hyphens, not pure hex)
    # This helps avoid unnecessary partial ID searches for app names
    if [[ "$identifier" =~ ^[a-z0-9-]+$ ]] && [[ ! "$identifier" =~ ^[a-f0-9]{16}$ ]]; then
        # Likely an app name, go directly to app resolution
        local deployment_id=$(get_active_deployment_for_app "$identifier")
        if [ -n "$deployment_id" ]; then
            echo "$deployment_id"
            return 0
        fi
        return 1
    fi
    
    # Try partial ID resolution only for potential partial IDs (hex patterns)
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
    
    # If partial resolution didn't work, try app name as fallback
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

    # Show header only if there are deployments to display
    if [ -z "$deployments" ]; then
        echo "(no deployments found)"
        return 0
    fi

    # Header aligned with data columns
    printf "%-16s %-19s %-9s %-15s %-9s %-9s %s\n" \
           "CONTAINER ID" "APP NAME" "STATUS" "IP ADDRESS" "CONTRACT" "SOURCE" "AGE"
    echo "────────────────────────────────────────────────────────────────────────────────────────"

    # Display all deployments
    echo "$deployments" | while IFS='|' read -r deployment_id app_name vm_ip contract_id status created_at origin; do
        local age=$(calculate_deployment_age "$created_at")
        local display_contract="$contract_id"
        if [ -z "$display_contract" ] || [ "$display_contract" = "unknown" ]; then
            display_contract="N/A"
        elif [ ${#display_contract} -gt 9 ]; then
            display_contract="${display_contract:0:9}..."
        fi

        # Best-effort: override vm_ip with full value from registry when yq is available
        if command_exists yq; then
            local full_vm_ip
            full_vm_ip=$(yq eval ".deployments.\"$deployment_id\".vm_ip // \"\"" "$DEPLOYMENT_REGISTRY" 2>/dev/null || echo "")
            if [ -n "$full_vm_ip" ]; then
                # If multiline, take the first non-empty line
                if [[ "$full_vm_ip" == *$'\n'* ]]; then
                    full_vm_ip=$(printf '%s\n' "$full_vm_ip" | sed -n '1{/^[[:space:]]*$/d;p}')
                fi
                vm_ip="$full_vm_ip"
            fi
        fi

        # Best-effort: infer origin (registry vs custom) when missing and yq + state_dir available
        if [ -z "$origin" ] && command_exists yq; then
            local state_dir=""
            state_dir=$(yq eval ".deployments.\"$deployment_id\".state_dir // \"\"" "$DEPLOYMENT_REGISTRY" 2>/dev/null || echo "")
            if [ -n "$state_dir" ] && [ -f "$state_dir/state.yaml" ] && [ -n "${APPS_CACHE_DIR:-}" ]; then
                local app_dir=""
                app_dir=$(grep "^app_dir:" "$state_dir/state.yaml" 2>/dev/null | head -n1 | awk '{print $2}' || echo "")
                if [ -n "$app_dir" ]; then
                    case "$app_dir" in
                        "$APPS_CACHE_DIR"/*)
                            origin="registry"
                            ;;
                        *)
                            origin="custom"
                            ;;
                    esac
                fi
            fi
        fi

        printf "%-16s %-19s %-9s %-15s %-9s %-9s %s\n" \
               "$deployment_id" \
               "${app_name:0:19}" \
               "${status:0:9}" \
               "$vm_ip" \
               "$display_contract" \
               "${origin:0:9}" \
               "$age"
    done
}

list_deployments_docker_style_outside() {
    local deployments_raw
    deployments_raw=$(get_all_deployments_raw 2>/dev/null || echo "")

    local registry_contract_ids
    registry_contract_ids=$(printf '%s\n' "$deployments_raw" | awk -F '|' 'NF>=4 && $4 != "" {print $4}' | sort -u || echo "")

    local contracts_output
    if ! contracts_output=$(timeout 15 bash -c "tfgrid-compose contracts list 2>/dev/null" 2>/dev/null); then
        echo "Deployments (Docker-style):"
        echo ""
        echo "(could not fetch contracts from tfgrid-compose)"
        return 1
    fi

    local outside_ids=""
    while IFS= read -r line; do
        if printf '%s\n' "$line" | grep -qE '^[0-9]+[[:space:]]'; then
            local cid
            cid=$(printf '%s\n' "$line" | awk '{print $1}')
            if [ -n "$cid" ]; then
                if [ -z "$registry_contract_ids" ] || ! printf '%s\n' "$registry_contract_ids" | grep -q -E "^${cid}$"; then
                    outside_ids="${outside_ids}${cid}\n"
                fi
            fi
        fi
    done <<< "$contracts_output"

    local unique_outside_ids
    unique_outside_ids=$(printf '%s\n' "$outside_ids" | sed '/^$/d' | sort -u || echo "")

    if [ -z "$unique_outside_ids" ]; then
        echo "Deployments (Docker-style):"
        echo ""
        echo "(no outside deployments found)"
        return 0
    fi

    echo "Deployments (Docker-style):"
    echo ""
    printf "%-16s %-19s %-9s %-15s %-9s %-9s %s\n" \
           "CONTAINER ID" "APP NAME" "STATUS" "IP ADDRESS" "CONTRACT" "SOURCE" "AGE"
    echo "────────────────────────────────────────────────────────────────────────────────────────"

    while IFS= read -r cid; do
        [ -z "$cid" ] && continue

        local app_name status vm_ip contract_id origin age display_contract
        app_name="vm"
        status="active"
        vm_ip="N/A"
        contract_id="$cid"
        origin="outside"
        age="unknown"

        display_contract="$contract_id"
        if [ -z "$display_contract" ] || [ "$display_contract" = "unknown" ]; then
            display_contract="N/A"
        elif [ ${#display_contract} -gt 9 ]; then
            display_contract="${display_contract:0:9}..."
        fi

        printf "%-16s %-19s %-9s %-15s %-9s %-9s %s\n" \
               "$cid" \
               "${app_name:0:19}" \
               "${status:0:9}" \
               "$vm_ip" \
               "$display_contract" \
               "${origin:0:9}" \
               "$age"
    done <<< "$unique_outside_ids"

    return 0
}

list_deployments_docker_style_active_contracts() {
    local deployments=$(get_all_deployments)

    if [ -z "$deployments" ]; then
        echo "Deployments (Docker-style):"
        echo ""
        echo "(no deployments found)"
        return 0
    fi

    local contracts_output=""
    if ! contracts_output=$(timeout 15 bash -c "tfgrid-compose contracts list 2>/dev/null" 2>/dev/null); then
        list_deployments_docker_style
        return 0
    fi

    local active_ids
    active_ids=$(printf '%s\n' "$contracts_output" | awk '/^[0-9]+[[:space:]]/ {print $1}')

    if [ -z "$active_ids" ]; then
        echo "Deployments (Docker-style):"
        echo ""
        echo "(no deployments with active contracts found)"
        return 0
    fi

    echo "Deployments (Docker-style):"
    echo ""
    # Header aligned with data columns
    printf "%-16s %-19s %-9s %-15s %-9s %-9s %s\n" \
           "CONTAINER ID" "APP NAME" "STATUS" "IP ADDRESS" "CONTRACT" "SOURCE" "AGE"
    echo "────────────────────────────────────────────────────────────────────────────────────────"

    echo "$deployments" | while IFS='|' read -r deployment_id app_name vm_ip contract_id status created_at origin; do
        if [ -z "$deployment_id" ]; then
            continue
        fi

        if [ -z "$contract_id" ] || [ "$contract_id" = "null" ]; then
            continue
        fi

        if ! printf '%s\n' "$active_ids" | grep -q -E "^${contract_id}$"; then
            continue
        fi

        local age
        age=$(calculate_deployment_age "$created_at")

        local origin=""

        if command_exists yq; then
            origin=$(yq eval ".deployments.\"$deployment_id\".origin // \"\"" "$DEPLOYMENT_REGISTRY" 2>/dev/null || echo "")
            if [ -z "$origin" ]; then
                local state_dir=""
                state_dir=$(yq eval ".deployments.\"$deployment_id\".state_dir // \"\"" "$DEPLOYMENT_REGISTRY" 2>/dev/null || echo "")
                if [ -n "$state_dir" ] && [ -f "$state_dir/state.yaml" ] && [ -n "${APPS_CACHE_DIR:-}" ]; then
                    local app_dir=""
                    app_dir=$(grep "^app_dir:" "$state_dir/state.yaml" 2>/dev/null | head -n1 | awk '{print $2}' || echo "")
                    if [ -n "$app_dir" ]; then
                        case "$app_dir" in
                            "$APPS_CACHE_DIR"/*)
                                origin="registry"
                                ;;
                            *)
                                origin="custom"
                                ;;
                        esac
                    fi
                fi
            fi

            # Also override vm_ip with the full value from the registry when available
            local full_vm_ip
            full_vm_ip=$(yq eval ".deployments.\"$deployment_id\".vm_ip // \"\"" "$DEPLOYMENT_REGISTRY" 2>/dev/null || echo "")
            if [ -n "$full_vm_ip" ]; then
                if [[ "$full_vm_ip" == *$'\n'* ]]; then
                    full_vm_ip=$(printf '%s\n' "$full_vm_ip" | sed -n '1{/^[[:space:]]*$/d;p}')
                fi
                vm_ip="$full_vm_ip"
            fi
        fi

        if [ -z "$origin" ]; then
            origin="unknown"
        fi

        local display_contract="$contract_id"
        if [ -z "$display_contract" ] || [ "$display_contract" = "unknown" ]; then
            display_contract="N/A"
        elif [ ${#display_contract} -gt 9 ]; then
            display_contract="${display_contract:0:9}..."
        fi

        printf "%-16s %-19s %-9s %-15s %-9s %-9s %s\n" \
               "$deployment_id" \
               "${app_name:0:19}" \
               "${status:0:9}" \
               "$vm_ip" \
               "$display_contract" \
               "${origin:0:9}" \
               "$age"
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
export -f list_deployments_docker_style_outside
export -f list_deployments_docker_style_active_contracts

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

    # Get current active contract IDs via tfgrid-compose contracts list
    local contracts_output
    if ! contracts_output=$(timeout 30 bash -c "tfgrid-compose contracts list 2>/dev/null" 2>/dev/null); then
        log_warning "Skipping deployment cleanup: could not fetch contracts from tfgrid-compose"
        return 0
    fi

    local active_ids
    active_ids=$(printf '%s\n' "$contracts_output" | awk '/^[0-9]+[[:space:]]/ {print $1}' | sort -u)

    if [ -z "$active_ids" ]; then
        log_warning "No active contracts found via tfgrid-compose; skipping deployment cleanup"
        return 0
    fi

    local cleaned_count=0

    while IFS='|' read -r deployment_id app_name vm_ip contract_id status created_at; do
        if [ -z "$deployment_id" ]; then
            continue
        fi

        if [ -n "$contract_id" ]; then
            # If this deployment's contract ID is not in the active list, remove it
            if ! printf '%s\n' "$active_ids" | grep -q -E "^${contract_id}$"; then
                log_info "Removing orphaned deployment: $deployment_id (contract $contract_id not found on grid)"
                unregister_deployment "$deployment_id"
                ((cleaned_count++))
            fi
        else
            # Registry entry without contract ID - likely old format, remove it
            log_info "Removing legacy deployment without contract ID: $deployment_id"
            unregister_deployment "$deployment_id"
            ((cleaned_count++))
        fi
    done <<< "$deployments"

    if [ $cleaned_count -gt 0 ]; then
        log_info "Cleaned up $cleaned_count orphaned deployment(s)"
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
