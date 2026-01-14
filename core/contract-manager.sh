#!/usr/bin/env bash
# Contract Manager - Simple tfcmd wrapper for TFGrid Compose

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Check if tfcmd is installed
check_tfcmd_installed() {
    if ! command -v tfcmd >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Load tfgrid-compose credentials
load_tfgrid_credentials() {
    # Load tfgrid-compose credentials
    if ! source "$SCRIPT_DIR/signin.sh" 2>/dev/null; then
        log_error "Could not load signin.sh"
        return 1
    fi

    if ! load_credentials; then
        log_error "Failed to load credentials"
        return 1
    fi

    if [ -z "$TFGRID_MNEMONIC" ]; then
        log_error "ThreeFold mnemonic not configured"
        log_info "Run 'tfgrid-compose signin' to configure credentials"
        return 1
    fi

    return 0
}

# Ensure tfcmd is configured with tfgrid-compose credentials
# tfcmd expects a config file at ~/.config/.tfgridconfig
ensure_tfcmd_config() {
    local tfcmd_config="$HOME/.config/.tfgridconfig"
    local network="${TFGRID_NETWORK:-main}"

    # Load credentials if not already loaded
    if [ -z "$TFGRID_MNEMONIC" ]; then
        if ! load_tfgrid_credentials; then
            return 1
        fi
    fi

    # Check if config exists and has correct mnemonic
    if [ -f "$tfcmd_config" ]; then
        local existing_mnemonic=$(grep -o '"mnemonics":"[^"]*"' "$tfcmd_config" 2>/dev/null | sed 's/"mnemonics":"//;s/"$//')
        local existing_network=$(grep -o '"network":"[^"]*"' "$tfcmd_config" 2>/dev/null | sed 's/"network":"//;s/"$//')

        if [ "$existing_mnemonic" = "$TFGRID_MNEMONIC" ] && [ "$existing_network" = "$network" ]; then
            # Config is already up to date
            return 0
        fi
    fi

    # Create/update tfcmd config with credentials from tfgrid-compose
    log_info "Syncing tfcmd config with tfgrid-compose credentials..."

    # Ensure config directory exists
    mkdir -p "$(dirname "$tfcmd_config")"

    # Write JSON config file
    cat > "$tfcmd_config" << EOF
{"mnemonics":"$TFGRID_MNEMONIC","network":"$network"}
EOF

    if [ $? -eq 0 ]; then
        chmod 600 "$tfcmd_config"
        log_success "tfcmd config synced"
        return 0
    else
        log_error "Failed to write tfcmd config"
        return 1
    fi
}

# Simple wrapper for tfcmd get contracts
contracts_list() {
    log_info "Fetching contracts via tfcmd..."

    if ! check_tfcmd_installed; then
        log_error "tfcmd not installed"
        log_info "Install tfcmd with: tfgrid-compose tfcmd-install"
        return 1
    fi

    # Ensure tfcmd config is synced with tfgrid-compose credentials
    if ! ensure_tfcmd_config; then
        return 1
    fi

    # Call tfcmd to get contracts
    if ! tfcmd get contracts; then
        log_error "Failed to fetch contracts via tfcmd"
        return 1
    fi

    return 0
}

# Simple wrapper for tfcmd delete contracts
contracts_delete() {
    local contract_id="$1"

    if [ -z "$contract_id" ]; then
        log_error "Contract ID required"
        echo ""
        echo "Usage: tfgrid-compose contracts delete <contract-id>"
        return 1
    fi

    log_info "Deleting contract $contract_id via tfcmd..."

    if ! check_tfcmd_installed; then
        log_error "tfcmd not installed"
        log_info "Install tfcmd with: tfgrid-compose tfcmd-install"
        return 1
    fi

    # Ensure tfcmd config is synced with tfgrid-compose credentials
    if ! ensure_tfcmd_config; then
        return 1
    fi

    # Call tfcmd to delete contract
    local output
    output=$(tfcmd cancel contracts "$contract_id" 2>&1)
    local exit_code=$?

    # Check if contract already doesn't exist (treat as success)
    if echo "$output" | grep -q "ContractNotExists"; then
        log_warning "Contract $contract_id already deleted (not found on grid)"
        return 0
    fi

    if [ $exit_code -ne 0 ]; then
        log_error "Failed to delete contract $contract_id via tfcmd"
        echo "$output" >&2
        return 1
    fi

    log_success "Contract $contract_id deleted successfully"

    # Auto-cleanup: Remove registry entry for this contract
    local registry_file="$HOME/.config/tfgrid-compose/deployments.yaml"
    if [ -f "$registry_file" ] && command_exists yq; then
        # Find deployment with this contract_id
        local deployment_id=$(yq eval ".deployments | to_entries | .[] | select(.value.contract_id == \"$contract_id\") | .key" "$registry_file" 2>/dev/null | head -1)
        if [ -n "$deployment_id" ]; then
            if yq eval "del(.deployments.\"$deployment_id\")" "$registry_file" > "${registry_file}.tmp" 2>/dev/null; then
                mv "${registry_file}.tmp" "$registry_file"
                log_info "Removed registry entry: $deployment_id"
            else
                rm -f "${registry_file}.tmp"
            fi
        fi
    fi

    return 0
}

# Simple wrapper for tfcmd cancel all contracts
contracts_cancel_all() {
    local skip_confirm="${1:-}"

    log_warning "This will cancel ALL contracts associated with your mnemonic!"
    echo ""
    echo "Contracts that will be cancelled:"
    echo "  • All active node contracts"
    echo "  • All active rent contracts"
    echo "  • All active deployment contracts"
    echo ""

    # Skip confirmation if --yes flag is passed
    if [ "$skip_confirm" != "--yes" ]; then
        read -p "Are you sure you want to cancel ALL contracts? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Cancelled by user"
            return 0
        fi
    else
        log_info "Auto-confirmed via --yes flag"
    fi

    if ! check_tfcmd_installed; then
        log_error "tfcmd not installed"
        log_info "Install tfcmd with: tfgrid-compose tfcmd-install"
        return 1
    fi

    # Ensure tfcmd config is synced with tfgrid-compose credentials
    if ! ensure_tfcmd_config; then
        return 1
    fi

    log_info "Cancelling ALL contracts via tfcmd..."
    echo ""
    echo "⚠️  This action cannot be undone!"
    echo ""

    # Call tfcmd to cancel all contracts
    if ! tfcmd cancel contracts -a; then
        log_error "Failed to cancel contracts via tfcmd"
        return 1
    fi

    log_success "All contracts cancelled successfully"
    echo ""
    log_info "Note: This may take a few minutes to complete on the grid"
    return 0
}

# Get state directory path
get_state_dir() {
    echo "${TFGRID_STATE_DIR:-$HOME/.config/tfgrid-compose/state}"
}

# Find container by partial ID (like docker)
find_container_by_prefix() {
    local prefix="$1"
    local state_dir=$(get_state_dir)
    local matches=()

    # Search through state directories for matching container IDs
    for dir in "$state_dir"/*/; do
        [ -d "$dir" ] || continue
        local container_id=$(basename "$dir")
        # Skip named directories (not hex IDs)
        [[ "$container_id" =~ ^[0-9a-f]+$ ]] || continue

        if [[ "$container_id" == "$prefix"* ]]; then
            matches+=("$container_id")
        fi
    done

    if [ ${#matches[@]} -eq 0 ]; then
        echo ""
        return 1
    elif [ ${#matches[@]} -eq 1 ]; then
        echo "${matches[0]}"
        return 0
    else
        # Multiple matches - return all for error message
        printf '%s\n' "${matches[@]}"
        return 2
    fi
}

# Get contracts for a container from its terraform state
get_container_contracts() {
    local container_id="$1"
    local state_dir=$(get_state_dir)
    local tf_state="$state_dir/$container_id/terraform/terraform.tfstate"

    if [ ! -f "$tf_state" ]; then
        return 1
    fi

    local contracts=()

    # Get VM/deployment contract IDs
    local vm_contracts=$(jq -r '.resources[] | select(.type == "grid_deployment") | .instances[].attributes.id // empty' "$tf_state" 2>/dev/null | grep -v null)
    for id in $vm_contracts; do
        [ -n "$id" ] && contracts+=("$id")
    done

    # Get network contract IDs from node_deployment_id map
    local net_contracts=$(jq -r '.resources[] | select(.type == "grid_network") | .instances[].attributes.node_deployment_id | values[]' "$tf_state" 2>/dev/null | grep -v null)
    for id in $net_contracts; do
        [ -n "$id" ] && contracts+=("$id")
    done

    # Output unique contracts
    printf '%s\n' "${contracts[@]}" | sort -u
}

# Get app name for a container
get_container_app_name() {
    local container_id="$1"
    local state_dir=$(get_state_dir)
    local state_yaml="$state_dir/$container_id/state.yaml"

    if [ -f "$state_yaml" ]; then
        grep "^app_name:" "$state_yaml" | sed 's/^app_name:[[:space:]]*//'
    else
        echo "(unknown)"
    fi
}

# Delete contracts by container ID
contracts_delete_by_container() {
    local prefix="$1"
    local skip_confirm="${2:-false}"

    # Find matching container
    local result
    result=$(find_container_by_prefix "$prefix")
    local status=$?

    if [ $status -eq 1 ]; then
        log_error "No container found matching: $prefix"
        echo ""
        echo "Use 't ps' to list active deployments or check state directories."
        return 1
    elif [ $status -eq 2 ]; then
        log_error "Ambiguous container ID: '$prefix' matches multiple containers:"
        echo "$result" | while read -r id; do
            local app=$(get_container_app_name "$id")
            echo "  - $id ($app)"
        done
        echo ""
        echo "Please use more characters to uniquely identify the container."
        return 1
    fi

    local container_id="$result"
    local app_name=$(get_container_app_name "$container_id")

    log_success "Matched container: $container_id ($app_name)"

    # Get contracts for this container
    local contracts
    contracts=$(get_container_contracts "$container_id")

    if [ -z "$contracts" ]; then
        log_warning "No contracts found in terraform state for this container"
        echo ""
        echo "The container may have been manually cleaned up or state is missing."
        return 0
    fi

    local contract_array=()
    while IFS= read -r id; do
        [ -n "$id" ] && contract_array+=("$id")
    done <<< "$contracts"

    echo ""
    echo "Contracts to delete:"
    for id in "${contract_array[@]}"; do
        echo "  - $id"
    done
    echo ""

    if [ "$skip_confirm" != "true" ]; then
        echo -n "Delete these contracts? (yes/no): "
        read -r confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Cancelled"
            return 0
        fi
    fi

    # Delete each contract
    local failed=0
    for id in "${contract_array[@]}"; do
        if ! contracts_delete "$id"; then
            failed=1
        fi
    done

    # Optionally clean up state directory
    if [ $failed -eq 0 ]; then
        local state_dir=$(get_state_dir)
        echo ""
        echo -n "Remove state directory for this deployment? (yes/no): "
        read -r rm_confirm
        if [ "$rm_confirm" = "yes" ]; then
            rm -rf "$state_dir/$container_id"
            log_success "State directory removed"
        fi
    fi

    return $failed
}

# Find orphaned contracts (not linked to active deployments)
contracts_orphans() {
    local do_delete="${1:-false}"
    local skip_confirm="${2:-false}"

    log_info "Scanning for orphaned contracts..."
    echo ""

    if ! check_tfcmd_installed; then
        log_error "tfcmd not installed"
        return 1
    fi

    # Ensure tfcmd config is synced with tfgrid-compose credentials
    if ! ensure_tfcmd_config; then
        return 1
    fi

    # Get all contracts from grid
    local all_contracts
    all_contracts=$(tfcmd get contracts 2>/dev/null | grep -E '^\s*[0-9]+' | awk '{print $1}')

    if [ -z "$all_contracts" ]; then
        log_info "No contracts found on grid"
        return 0
    fi

    # Get contracts from active deployments
    local state_dir=$(get_state_dir)
    local config_dir="${TFGRID_CONFIG_DIR:-$HOME/.config/tfgrid-compose}"
    local active_contracts=()

    # Method 1: Check each state directory for terraform state with contracts
    for dir in "$state_dir"/*/; do
        [ -d "$dir" ] || continue
        local tf_state="$dir/terraform/terraform.tfstate"
        [ -f "$tf_state" ] || continue

        # Extract contracts from this state
        local state_contracts=$(get_container_contracts "$(basename "$dir")")
        while IFS= read -r id; do
            [ -n "$id" ] && active_contracts+=("$id")
        done <<< "$state_contracts"
    done

    # Method 2: Also check deployments.yaml for tracked contracts
    local deployments_file="$config_dir/deployments.yaml"
    if [ -f "$deployments_file" ]; then
        local yaml_contracts=$(grep "contract_id:" "$deployments_file" 2>/dev/null | sed 's/.*contract_id:[[:space:]]*"\?\([0-9]*\)"\?.*/\1/' | grep -E '^[0-9]+$')
        while IFS= read -r id; do
            [ -n "$id" ] && active_contracts+=("$id")
        done <<< "$yaml_contracts"
    fi

    # Find orphaned contracts (in grid but not in any state)
    local orphaned=()
    while IFS= read -r contract_id; do
        [ -z "$contract_id" ] && continue
        local is_active=false
        for active in "${active_contracts[@]}"; do
            if [ "$contract_id" = "$active" ]; then
                is_active=true
                break
            fi
        done
        if [ "$is_active" = "false" ]; then
            orphaned+=("$contract_id")
        fi
    done <<< "$all_contracts"

    if [ ${#orphaned[@]} -eq 0 ]; then
        log_success "No orphaned contracts found"
        return 0
    fi

    echo "Found ${#orphaned[@]} orphaned contracts:"
    echo ""
    printf "  CONTRACT ID\n"
    printf "  ───────────\n"
    for id in "${orphaned[@]}"; do
        printf "  %s\n" "$id"
    done
    echo ""

    if [ "$do_delete" = "true" ]; then
        if [ "$skip_confirm" != "true" ]; then
            echo -n "Delete ${#orphaned[@]} orphaned contracts? (yes/no): "
            read -r confirm
            if [ "$confirm" != "yes" ]; then
                log_info "Cancelled"
                return 0
            fi
        fi

        local failed=0
        for id in "${orphaned[@]}"; do
            if ! contracts_delete "$id"; then
                failed=1
            fi
        done

        if [ $failed -eq 0 ]; then
            log_success "All orphaned contracts deleted"
        else
            log_warning "Some contracts failed to delete"
        fi
        return $failed
    else
        echo "Run 't contracts orphans --delete' to remove these contracts."
    fi

    return 0
}

# Interactive contract cleanup
contracts_clean_interactive() {
    log_info "Interactive Contract Cleanup"
    echo ""

    if ! check_tfcmd_installed; then
        log_error "tfcmd not installed"
        return 1
    fi

    # Ensure tfcmd config is synced with tfgrid-compose credentials
    if ! ensure_tfcmd_config; then
        return 1
    fi

    # Get all contracts that actually exist on the grid
    log_info "Fetching contracts from grid..."
    local grid_contracts_raw
    grid_contracts_raw=$(tfcmd get contracts 2>/dev/null | grep -E '^\s*[0-9]+' | awk '{print $1}')

    # Build a lookup set of existing contracts
    declare -A grid_contracts_set
    while IFS= read -r cid; do
        [ -n "$cid" ] && grid_contracts_set["$cid"]=1
    done <<< "$grid_contracts_raw"

    # Group contracts by network name/deployment
    local state_dir=$(get_state_dir)
    local deployments=()
    local deployment_contracts=()
    local deployment_names=()
    local deployment_stale_contracts=()
    local idx=0

    # First, collect known deployments from state directories
    for dir in "$state_dir"/*/; do
        [ -d "$dir" ] || continue
        local container_id=$(basename "$dir")
        local state_yaml="$dir/state.yaml"
        local tf_state="$dir/terraform/terraform.tfstate"

        local app_name="(unknown)"
        [ -f "$state_yaml" ] && app_name=$(grep "^app_name:" "$state_yaml" | sed 's/^app_name:[[:space:]]*//')

        # Get contracts from local state
        local local_contracts=""
        local active_contracts=""
        local stale_count=0
        if [ -f "$tf_state" ]; then
            local_contracts=$(get_container_contracts "$container_id" | tr '\n' ',' | sed 's/,$//')
            # Filter to only contracts that exist on grid
            IFS=',' read -ra contract_arr <<< "$local_contracts"
            for c in "${contract_arr[@]}"; do
                if [ -n "${grid_contracts_set[$c]:-}" ]; then
                    [ -n "$active_contracts" ] && active_contracts="$active_contracts,"
                    active_contracts="$active_contracts$c"
                else
                    stale_count=$((stale_count + 1))
                fi
            done
        fi

        # Include deployment if it has local state (even if no active contracts - for cleanup)
        if [ -n "$local_contracts" ]; then
            idx=$((idx + 1))
            deployments+=("$container_id")
            deployment_contracts+=("$active_contracts")
            deployment_names+=("$app_name")
            deployment_stale_contracts+=("$stale_count")
        fi
    done

    if [ $idx -eq 0 ]; then
        log_info "No deployments found with contract state"
        echo ""
        echo "Use 't contracts orphans' to find orphaned contracts."
        return 0
    fi

    # Auto-cleanup stale state directories (no contracts on grid)
    local stale_dirs=()
    local active_deployments=()
    local active_contracts=()
    local active_names=()
    local active_stale=()

    for i in "${!deployments[@]}"; do
        if [ -z "${deployment_contracts[$i]}" ]; then
            stale_dirs+=("${deployments[$i]}")
        else
            active_deployments+=("${deployments[$i]}")
            active_contracts+=("${deployment_contracts[$i]}")
            active_names+=("${deployment_names[$i]}")
            active_stale+=("${deployment_stale_contracts[$i]}")
        fi
    done

    # Auto-remove stale directories
    if [ ${#stale_dirs[@]} -gt 0 ]; then
        log_info "Found ${#stale_dirs[@]} stale state directories (no contracts on grid)"
        for dir in "${stale_dirs[@]}"; do
            rm -rf "$state_dir/$dir"
            echo "  Removed stale: ${dir:0:16}.."
        done
        log_success "Stale state directories cleaned up"
        echo ""
    fi

    # Update arrays to only active deployments
    deployments=("${active_deployments[@]}")
    deployment_contracts=("${active_contracts[@]}")
    deployment_names=("${active_names[@]}")
    deployment_stale_contracts=("${active_stale[@]}")
    idx=${#deployments[@]}

    if [ $idx -eq 0 ]; then
        log_info "No active deployments remaining"
        return 0
    fi

    # Display active deployments
    echo "Found $idx active deployments with contracts:"
    echo ""
    printf "  #   %-18s %-25s %-12s %s\n" "CONTAINER ID" "APP NAME" "STATUS" "CONTRACTS"
    printf "  ─── ────────────────── ───────────────────────── ──────────── ────────────────────\n"

    for i in "${!deployments[@]}"; do
        local num=$((i + 1))
        local status="active"
        local contracts_display="${deployment_contracts[$i]}"
        if [ "${deployment_stale_contracts[$i]}" -gt 0 ]; then
            status="partial"
        fi
        printf "  %-3d %-18s %-25s %-12s %s\n" "$num" "${deployments[$i]:0:16}.." "${deployment_names[$i]:0:23}" "$status" "$contracts_display"
    done
    echo ""

    echo "Enter deployments to delete (e.g., 1,2 or 1-3 or 'all'), or 'exit' to quit:"
    echo -n "> "
    read -r selection

    if [ -z "$selection" ] || [ "$selection" = "exit" ] || [ "$selection" = "quit" ] || [ "$selection" = "q" ]; then
        log_info "Exiting"
        return 0
    fi

    # Parse selection
    local to_delete=()
    if [ "$selection" = "all" ]; then
        to_delete=("${!deployments[@]}")
    else
        # Parse comma-separated and ranges
        IFS=',' read -ra parts <<< "$selection"
        for part in "${parts[@]}"; do
            part=$(echo "$part" | tr -d ' ')
            if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                # Range
                local start="${BASH_REMATCH[1]}"
                local end="${BASH_REMATCH[2]}"
                for ((n=start; n<=end; n++)); do
                    [ $n -ge 1 ] && [ $n -le $idx ] && to_delete+=($((n - 1)))
                done
            elif [[ "$part" =~ ^[0-9]+$ ]]; then
                # Single number
                [ "$part" -ge 1 ] && [ "$part" -le $idx ] && to_delete+=($((part - 1)))
            fi
        done
    fi

    if [ ${#to_delete[@]} -eq 0 ]; then
        log_error "Invalid selection"
        return 1
    fi

    # Collect all contracts to delete (only active ones on grid)
    local all_contracts_to_delete=()
    echo ""
    echo "Will process:"
    for i in "${to_delete[@]}"; do
        local active_count=0
        if [ -n "${deployment_contracts[$i]}" ]; then
            IFS=',' read -ra contracts <<< "${deployment_contracts[$i]}"
            for c in "${contracts[@]}"; do
                [ -n "$c" ] && all_contracts_to_delete+=("$c") && active_count=$((active_count + 1))
            done
        fi
        echo "  - ${deployment_names[$i]} (${deployments[$i]:0:16}..) - $active_count active contracts"
    done
    echo ""

    if [ ${#all_contracts_to_delete[@]} -gt 0 ]; then
        echo "Total contracts to delete: ${#all_contracts_to_delete[@]}"
    else
        echo "No active contracts to delete (only stale state to clean up)"
    fi
    echo ""

    echo -n "Confirm? (yes/no): "
    read -r confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Cancelled"
        return 0
    fi

    # Delete contracts (only if there are any)
    local failed=0
    if [ ${#all_contracts_to_delete[@]} -gt 0 ]; then
        for id in "${all_contracts_to_delete[@]}"; do
            if ! contracts_delete "$id"; then
                failed=1
            fi
        done
    fi

    # Always offer to clean up state directories (contracts may already be gone from grid)
    echo ""
    echo -n "Remove state directories for these deployments? (yes/no): "
    read -r rm_confirm
    if [ "$rm_confirm" = "yes" ]; then
        for i in "${to_delete[@]}"; do
            rm -rf "$state_dir/${deployments[$i]}"
            echo "  Removed: ${deployments[$i]}"
        done
        log_success "State directories cleaned up"
    fi

    return 0
}

# List all state directories
state_list() {
    local state_dir=$(get_state_dir)

    if [ ! -d "$state_dir" ]; then
        log_info "No state directory found"
        return 0
    fi

    local count=0
    printf "  %-18s %-25s %-12s %s\n" "CONTAINER ID" "APP NAME" "AGE" "HAS CONTRACTS"
    printf "  ────────────────── ───────────────────────── ──────────── ─────────────\n"

    for dir in "$state_dir"/*/; do
        [ -d "$dir" ] || continue
        local container_id=$(basename "$dir")
        local state_yaml="$dir/state.yaml"
        local tf_state="$dir/terraform/terraform.tfstate"

        local app_name="(unknown)"
        [ -f "$state_yaml" ] && app_name=$(grep "^app_name:" "$state_yaml" 2>/dev/null | sed 's/^app_name:[[:space:]]*//')

        local has_contracts="no"
        if [ -f "$tf_state" ]; then
            local contracts=$(get_container_contracts "$container_id" 2>/dev/null)
            [ -n "$contracts" ] && has_contracts="yes"
        fi

        # Get age
        local age="unknown"
        if [ -f "$state_yaml" ]; then
            local created=$(stat -c %Y "$state_yaml" 2>/dev/null || stat -f %m "$state_yaml" 2>/dev/null)
            if [ -n "$created" ]; then
                local now=$(date +%s)
                local diff=$((now - created))
                if [ $diff -lt 3600 ]; then
                    age="$((diff / 60))m ago"
                elif [ $diff -lt 86400 ]; then
                    age="$((diff / 3600))h ago"
                else
                    age="$((diff / 86400))d ago"
                fi
            fi
        fi

        printf "  %-18s %-25s %-12s %s\n" "${container_id:0:16}.." "${app_name:0:23}" "$age" "$has_contracts"
        count=$((count + 1))
    done

    echo ""
    log_info "Total: $count state directories"
}

# Clean orphaned state directories
state_clean() {
    local force=false
    local dry_run=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --force|-f) force=true; shift ;;
            --dry-run|-n) dry_run=true; shift ;;
            *) log_error "Unknown option: $1"; return 1 ;;
        esac
    done

    local state_dir=$(get_state_dir)

    if [ ! -d "$state_dir" ]; then
        log_info "No state directory found"
        return 0
    fi

    # Get active contracts from grid
    log_info "Fetching active contracts from grid..."

    if ! check_tfcmd_installed; then
        log_error "tfcmd not installed"
        return 1
    fi

    # Ensure tfcmd config is synced with tfgrid-compose credentials
    if ! ensure_tfcmd_config; then
        return 1
    fi

    local active_contracts
    active_contracts=$(tfcmd get contracts 2>/dev/null | grep -E '^\s*[0-9]+' | awk '{print $1}')

    # Find orphaned state directories
    local orphaned=()
    local orphaned_names=()

    for dir in "$state_dir"/*/; do
        [ -d "$dir" ] || continue
        local container_id=$(basename "$dir")
        local tf_state="$dir/terraform/terraform.tfstate"
        local state_yaml="$dir/state.yaml"

        # Get app name
        local app_name="(unknown)"
        [ -f "$state_yaml" ] && app_name=$(grep "^app_name:" "$state_yaml" 2>/dev/null | sed 's/^app_name:[[:space:]]*//')

        # Check if any contracts from this state are still active
        local has_active=false
        if [ -f "$tf_state" ]; then
            local state_contracts=$(get_container_contracts "$container_id" 2>/dev/null)
            while IFS= read -r contract_id; do
                [ -z "$contract_id" ] && continue
                if echo "$active_contracts" | grep -q "^${contract_id}$"; then
                    has_active=true
                    break
                fi
            done <<< "$state_contracts"
        fi

        if [ "$has_active" = "false" ]; then
            orphaned+=("$container_id")
            orphaned_names+=("$app_name")
        fi
    done

    if [ ${#orphaned[@]} -eq 0 ]; then
        log_success "No orphaned state directories found"
    else
        echo "Found ${#orphaned[@]} orphaned state directories:"
        echo ""
        for i in "${!orphaned[@]}"; do
            echo "  - ${orphaned[$i]} (${orphaned_names[$i]})"
        done
        echo ""

        if [ "$dry_run" = "true" ]; then
            log_info "Dry run - no directories removed"
        elif [ "$force" != "true" ]; then
            echo -n "Remove ${#orphaned[@]} orphaned state directories? (yes/no): "
            read -r confirm
            if [ "$confirm" = "yes" ]; then
                # Remove orphaned directories
                local removed=0
                for container_id in "${orphaned[@]}"; do
                    rm -rf "$state_dir/$container_id"
                    echo "  Removed state dir: $container_id"
                    removed=$((removed + 1))
                done
                log_success "Removed $removed orphaned state directories"
            else
                log_info "Skipped state directory cleanup"
            fi
        else
            # Force mode - remove without prompting
            local removed=0
            for container_id in "${orphaned[@]}"; do
                rm -rf "$state_dir/$container_id"
                echo "  Removed state dir: $container_id"
                removed=$((removed + 1))
            done
            log_success "Removed $removed orphaned state directories"
        fi
    fi

    # Also clean up registry entries without active contracts
    echo ""
    log_info "Checking registry for orphaned entries..."

    local registry_file="$HOME/.config/tfgrid-compose/deployments.yaml"
    if [ ! -f "$registry_file" ]; then
        log_info "No registry file found"
        return 0
    fi

    if ! command_exists yq; then
        log_warning "yq not available, skipping registry cleanup"
        return 0
    fi

    # Get all deployment IDs from registry
    local registry_ids=$(yq eval '.deployments | keys | .[]' "$registry_file" 2>/dev/null || echo "")
    if [ -z "$registry_ids" ]; then
        log_info "Registry is empty"
        return 0
    fi

    # Find registry entries without active contracts
    local orphaned_registry=()
    local orphaned_registry_names=()

    while read -r deployment_id; do
        [ -z "$deployment_id" ] && continue

        local contract_id=$(yq eval ".deployments.\"$deployment_id\".contract_id // \"\"" "$registry_file" 2>/dev/null)
        local app_name=$(yq eval ".deployments.\"$deployment_id\".app_name // \"unknown\"" "$registry_file" 2>/dev/null)
        local entry_state_dir=$(yq eval ".deployments.\"$deployment_id\".state_dir // \"\"" "$registry_file" 2>/dev/null)

        # Check if this deployment is still valid
        local is_valid=false

        # Case 1: Has a contract_id that's still active on the grid
        if [ -n "$contract_id" ] && [ "$contract_id" != "null" ] && [ "$contract_id" != "" ]; then
            if echo "$active_contracts" | grep -q "^${contract_id}$"; then
                is_valid=true
            fi
        fi

        # Case 2: No contract_id but state directory still exists (deployment in progress)
        if [ "$is_valid" = "false" ] && [ -n "$entry_state_dir" ] && [ -d "$entry_state_dir" ]; then
            # State dir exists - check if it has active contracts in terraform state
            local tf_state="$entry_state_dir/terraform/terraform.tfstate"
            if [ -f "$tf_state" ]; then
                # Match both "id":"123" and "id": "123" formats
                local state_contracts=$(grep -oE '"id"[[:space:]]*:[[:space:]]*"?[0-9]+"?' "$tf_state" 2>/dev/null | grep -oE '[0-9]+' || echo "")
                while IFS= read -r cid; do
                    [ -z "$cid" ] && continue
                    if echo "$active_contracts" | grep -q "^${cid}$"; then
                        is_valid=true
                        break
                    fi
                done <<< "$state_contracts"
            fi
        fi

        if [ "$is_valid" = "false" ]; then
            orphaned_registry+=("$deployment_id")
            orphaned_registry_names+=("$app_name")
        fi
    done <<< "$registry_ids"

    if [ ${#orphaned_registry[@]} -eq 0 ]; then
        log_success "No orphaned registry entries found"
        return 0
    fi

    echo ""
    echo "Found ${#orphaned_registry[@]} orphaned registry entries:"
    echo ""
    for i in "${!orphaned_registry[@]}"; do
        echo "  - ${orphaned_registry[$i]} (${orphaned_registry_names[$i]})"
    done
    echo ""

    if [ "$dry_run" = "true" ]; then
        log_info "Dry run - no registry entries removed"
        return 0
    fi

    if [ "$force" != "true" ]; then
        echo -n "Remove ${#orphaned_registry[@]} orphaned registry entries? (yes/no): "
        read -r confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Cancelled"
            return 0
        fi
    fi

    # Remove orphaned registry entries
    local removed_registry=0
    for deployment_id in "${orphaned_registry[@]}"; do
        if yq eval "del(.deployments.\"$deployment_id\")" "$registry_file" > "${registry_file}.tmp" 2>/dev/null; then
            mv "${registry_file}.tmp" "$registry_file"
            echo "  Removed from registry: $deployment_id"
            removed_registry=$((removed_registry + 1))
        else
            rm -f "${registry_file}.tmp"
            log_warning "Failed to remove registry entry: $deployment_id"
        fi
    done

    log_success "Removed $removed_registry orphaned registry entries"
    return 0
}
