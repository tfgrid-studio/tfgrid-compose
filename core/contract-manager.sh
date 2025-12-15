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
    if ! source "$SCRIPT_DIR/login.sh" 2>/dev/null; then
        log_error "Could not load login.sh"
        return 1
    fi
    
    if ! load_credentials; then
        log_error "Failed to load credentials"
        return 1
    fi
    
    if [ -z "$TFGRID_MNEMONIC" ]; then
        log_error "ThreeFold mnemonic not configured"
        log_info "Run 'tfgrid-compose login' to configure credentials"
        return 1
    fi
    
    return 0
}

# Simple wrapper for tfcmd get contracts
contracts_list() {
    log_info "Fetching contracts via tfcmd..."
    
    if ! check_tfcmd_installed; then
        log_error "tfcmd not installed"
        log_info "Install tfcmd with: tfgrid-compose tfcmd-install"
        return 1
    fi
    
    # Load credentials and use mnemonic directly
    if ! load_tfgrid_credentials; then
        return 1
    fi
    
    # Call tfcmd to get contracts using mnemonic
    if ! echo "$TFGRID_MNEMONIC" | tfcmd get contracts; then
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
    
    # Load credentials and use mnemonic directly
    if ! load_tfgrid_credentials; then
        return 1
    fi
    
    # Call tfcmd to delete contract using mnemonic
    if ! echo "$TFGRID_MNEMONIC" | tfcmd cancel contracts "$contract_id"; then
        log_error "Failed to delete contract $contract_id via tfcmd"
        return 1
    fi
    
    log_success "Contract $contract_id deleted successfully"
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
    
    # Load credentials and use mnemonic directly
    if ! load_tfgrid_credentials; then
        return 1
    fi
    
    log_info "Cancelling ALL contracts via tfcmd..."
    echo ""
    echo "⚠️  This action cannot be undone!"
    echo ""
    
    # Call tfcmd to cancel all contracts using mnemonic
    if ! echo "$TFGRID_MNEMONIC" | tfcmd cancel contracts -a; then
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
    
    if ! load_tfgrid_credentials; then
        return 1
    fi
    
    # Get all contracts from grid
    local all_contracts
    all_contracts=$(echo "$TFGRID_MNEMONIC" | tfcmd get contracts 2>/dev/null | grep -E '^\s*[0-9]+' | awk '{print $1}')
    
    if [ -z "$all_contracts" ]; then
        log_info "No contracts found on grid"
        return 0
    fi
    
    # Get contracts from active deployments (via t ps)
    local state_dir=$(get_state_dir)
    local active_contracts=()
    
    # Check each state directory for terraform state with contracts
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
    
    if ! load_tfgrid_credentials; then
        return 1
    fi
    
    # Get all contracts from grid and parse them
    local contracts_raw
    contracts_raw=$(echo "$TFGRID_MNEMONIC" | tfcmd get contracts 2>/dev/null)
    
    # Group contracts by network name/deployment
    local state_dir=$(get_state_dir)
    local deployments=()
    local deployment_contracts=()
    local deployment_names=()
    local idx=0
    
    # First, collect known deployments from state directories
    for dir in "$state_dir"/*/; do
        [ -d "$dir" ] || continue
        local container_id=$(basename "$dir")
        local state_yaml="$dir/state.yaml"
        local tf_state="$dir/terraform/terraform.tfstate"
        
        local app_name="(unknown)"
        [ -f "$state_yaml" ] && app_name=$(grep "^app_name:" "$state_yaml" | sed 's/^app_name:[[:space:]]*//')
        
        local contracts=""
        if [ -f "$tf_state" ]; then
            contracts=$(get_container_contracts "$container_id" | tr '\n' ',' | sed 's/,$//')
        fi
        
        if [ -n "$contracts" ]; then
            idx=$((idx + 1))
            deployments+=("$container_id")
            deployment_contracts+=("$contracts")
            deployment_names+=("$app_name")
        fi
    done
    
    if [ $idx -eq 0 ]; then
        log_info "No deployments found with contract state"
        echo ""
        echo "Use 't contracts orphans' to find orphaned contracts."
        return 0
    fi
    
    # Display deployments
    echo "Found $idx deployments with contracts:"
    echo ""
    printf "  #   %-18s %-25s %s\n" "CONTAINER ID" "APP NAME" "CONTRACTS"
    printf "  ─── ────────────────── ───────────────────────── ────────────────────\n"
    
    for i in "${!deployments[@]}"; do
        local num=$((i + 1))
        printf "  %-3d %-18s %-25s %s\n" "$num" "${deployments[$i]:0:16}.." "${deployment_names[$i]:0:23}" "${deployment_contracts[$i]}"
    done
    echo ""
    
    echo "Enter deployments to delete (e.g., 1,2 or 1-3 or 'all'):"
    echo -n "> "
    read -r selection
    
    if [ -z "$selection" ]; then
        log_info "No selection made"
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
    
    # Collect all contracts to delete
    local all_contracts_to_delete=()
    echo ""
    echo "Will delete contracts from:"
    for i in "${to_delete[@]}"; do
        echo "  - ${deployment_names[$i]} (${deployments[$i]:0:16}..)"
        IFS=',' read -ra contracts <<< "${deployment_contracts[$i]}"
        for c in "${contracts[@]}"; do
            all_contracts_to_delete+=("$c")
        done
    done
    echo ""
    echo "Total contracts: ${#all_contracts_to_delete[@]}"
    echo ""
    
    echo -n "Confirm deletion? (yes/no): "
    read -r confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Cancelled"
        return 0
    fi
    
    # Delete contracts
    local failed=0
    for id in "${all_contracts_to_delete[@]}"; do
        if ! contracts_delete "$id"; then
            failed=1
        fi
    done
    
    # Clean up state directories
    if [ $failed -eq 0 ]; then
        echo ""
        echo -n "Remove state directories for deleted deployments? (yes/no): "
        read -r rm_confirm
        if [ "$rm_confirm" = "yes" ]; then
            for i in "${to_delete[@]}"; do
                rm -rf "$state_dir/${deployments[$i]}"
                echo "  Removed: ${deployments[$i]}"
            done
            log_success "State directories cleaned up"
        fi
    fi
    
    return $failed
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
    
    if ! load_tfgrid_credentials; then
        return 1
    fi
    
    local active_contracts
    active_contracts=$(echo "$TFGRID_MNEMONIC" | tfcmd get contracts 2>/dev/null | grep -E '^\s*[0-9]+' | awk '{print $1}')
    
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
        return 0
    fi
    
    echo "Found ${#orphaned[@]} orphaned state directories:"
    echo ""
    for i in "${!orphaned[@]}"; do
        echo "  - ${orphaned[$i]} (${orphaned_names[$i]})"
    done
    echo ""
    
    if [ "$dry_run" = "true" ]; then
        log_info "Dry run - no directories removed"
        return 0
    fi
    
    if [ "$force" != "true" ]; then
        echo -n "Remove ${#orphaned[@]} orphaned state directories? (yes/no): "
        read -r confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Cancelled"
            return 0
        fi
    fi
    
    # Remove orphaned directories
    local removed=0
    for container_id in "${orphaned[@]}"; do
        rm -rf "$state_dir/$container_id"
        echo "  Removed: $container_id"
        removed=$((removed + 1))
    done
    
    log_success "Removed $removed orphaned state directories"
    return 0
}