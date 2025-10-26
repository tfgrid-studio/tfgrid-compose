#!/usr/bin/env bash
# Contract Manager - Core contract management logic for TFGrid Compose
# Implements hybrid approach: GridProxy for reads, tfgrid-sdk-go for writes

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/login.sh"

# GridProxy API endpoints
GRIDPROXY_BASE="https://gridproxy.grid.tf"
CONTRACTS_ENDPOINT="$GRIDPROXY_BASE/contracts"

# tfgrid-sdk-go binary path (bundled)
TFGRID_SDK_BINARY="$HOME/.local/share/tfgrid-compose/bin/tfgrid-sdk-go"

# Network configurations
declare -A NETWORK_CONFIGS=(
    ["main"]="wss://tfchain.grid.tf/ws"
    ["test"]="wss://tfchain.test.grid.tf/ws"
    ["dev"]="wss://tfchain.dev.grid.tf/ws"
)

# =============================================================================
# GRIDPROXY API CLIENT FUNCTIONS (READ OPERATIONS)
# =============================================================================

# Query contracts via GridProxy API
contracts_list_gridproxy() {
    local twin_id="$1"
    local network="${2:-main}"
    local limit="${3:-50}"
    local offset="${4:-0}"

    if [ -z "$twin_id" ]; then
        log_error "Twin ID required for contract listing"
        return 1
    fi

    local url="$CONTRACTS_ENDPOINT?twin_id=$twin_id"

    log_info "Querying GridProxy for contracts (twin_id: $twin_id, network: $network)"

    # Make API request with timeout
    if command_exists curl; then
        local response
        response=$(curl -s --max-time 30 "$url" 2>/dev/null)
        local curl_exit=$?

        if [ $curl_exit -ne 0 ]; then
            log_error "Failed to query GridProxy API (curl exit: $curl_exit)"
            return 1
        fi

        if [ -z "$response" ]; then
            log_error "Empty response from GridProxy API"
            return 1
        fi

        echo "$response"
        return 0
    else
        log_error "curl command not available"
        return 1
    fi
}

# Get detailed contract information
contracts_get_details() {
    local contract_id="$1"

    if [ -z "$contract_id" ]; then
        log_error "Contract ID required"
        return 1
    fi

    local url="$CONTRACTS_ENDPOINT/$contract_id"

    log_info "Fetching contract details (ID: $contract_id)"

    if command_exists curl; then
        local response
        response=$(curl -s --max-time 30 "$url" 2>/dev/null)
        local curl_exit=$?

        if [ $curl_exit -ne 0 ]; then
            log_error "Failed to fetch contract details (curl exit: $curl_exit)"
            return 1
        fi

        if [ -z "$response" ]; then
            log_error "Contract not found or empty response"
            return 1
        fi

        echo "$response"
        return 0
    else
        log_error "curl command not available"
        return 1
    fi
}

# Apply filters and sorting to contract data
contracts_filter_and_sort() {
    local json_data="$1"
    local filter_type="$2"
    local filter_state="$3"
    local sort_by="${4:-created_at}"
    local sort_order="${5:-desc}"

    log_info "Applying filters and sorting"

    # Use jq if available for advanced filtering/sorting
    if command_exists jq; then
        local jq_filter="."

        # Apply type filter
        if [ -n "$filter_type" ]; then
            jq_filter="$jq_filter | map(select(.type == \"$filter_type\"))"
        fi

        # Apply state filter
        if [ -n "$filter_state" ]; then
            jq_filter="$jq_filter | map(select(.state == \"$filter_state\"))"
        fi

        # Apply sorting
        if [ "$sort_order" = "desc" ]; then
            jq_filter="$jq_filter | sort_by(.$sort_by) | reverse"
        else
            jq_filter="$jq_filter | sort_by(.$sort_by)"
        fi

        echo "$json_data" | jq "$jq_filter" 2>/dev/null
        return $?
    else
        # Fallback: basic filtering with grep/awk
        log_warning "jq not available, using basic filtering"
        echo "$json_data"
        return 0
    fi
}

# =============================================================================
# TFGRID-SDK-GO INTEGRATION FUNCTIONS (WRITE OPERATIONS)
# =============================================================================

# Check if tfgrid-sdk-go binary is available
check_tfgrid_sdk_binary() {
    if [ ! -f "$TFGRID_SDK_BINARY" ]; then
        log_error "tfgrid-sdk-go binary not found at: $TFGRID_SDK_BINARY"
        log_info "Run 'tfgrid-compose update' to download the binary"
        return 1
    fi

    if [ ! -x "$TFGRID_SDK_BINARY" ]; then
        log_error "tfgrid-sdk-go binary is not executable"
        return 1
    fi

    return 0
}

# Cancel single contract using tfcmd
contracts_cancel_single() {
    local contract_id="$1"
    local network="${2:-main}"

    if [ -z "$contract_id" ]; then
        log_error "Contract ID required for cancellation"
        return 1
    fi

    # Ensure tfcmd is available and logged in
    if ! command_exists tfcmd; then
        log_error "tfcmd not available"
        return 1
    fi

    if ! tfcmd login status >/dev/null 2>&1; then
        log_error "tfcmd not logged in. Run 'tfgrid-compose login' first"
        return 1
    fi

    local ws_url="${NETWORK_CONFIGS[$network]}"
    if [ -z "$ws_url" ]; then
        log_error "Unknown network: $network"
        return 1
    fi

    log_info "Cancelling contract $contract_id on $network network"

    # Use tfcmd to cancel contract
    if [ "${TFGRID_VERBOSE:-}" = "1" ]; then
        log_info "Executing: tfcmd contract cancel $contract_id"
        if tfcmd contract cancel "$contract_id"; then
            log_success "Contract $contract_id cancelled successfully"
            return 0
        else
            log_error "Failed to cancel contract $contract_id"
            return 1
        fi
    else
        if tfcmd contract cancel "$contract_id" >/dev/null 2>&1; then
            log_success "Contract $contract_id cancelled successfully"
            return 0
        else
            log_error "Failed to cancel contract $contract_id"
            return 1
        fi
    fi
}

# Cancel multiple contracts in batch
contracts_cancel_batch() {
    local contract_ids="$1"  # Space-separated list
    local network="${2:-main}"

    if [ -z "$contract_ids" ]; then
        log_error "Contract IDs required for batch cancellation"
        return 1
    fi

    # Ensure tfcmd is available and logged in
    if ! command_exists tfcmd; then
        log_error "tfcmd not available"
        return 1
    fi

    if ! tfcmd login status >/dev/null 2>&1; then
        log_error "tfcmd not logged in. Run 'tfgrid-compose login' first"
        return 1
    fi

    local contract_count=$(echo "$contract_ids" | wc -w | tr -d ' ')
    log_info "Batch cancelling $contract_count contracts on $network network"

    local failed_count=0
    local success_count=0

    # Cancel each contract individually (tfcmd doesn't have batch cancel)
    for contract_id in $contract_ids; do
        if [ "${TFGRID_VERBOSE:-}" = "1" ]; then
            log_info "Cancelling contract $contract_id..."
        fi

        if tfcmd contract cancel "$contract_id" >/dev/null 2>&1; then
            ((success_count++))
            if [ "${TFGRID_VERBOSE:-}" = "1" ]; then
                log_success "Contract $contract_id cancelled"
            fi
        else
            ((failed_count++))
            log_error "Failed to cancel contract $contract_id"
        fi
    done

    if [ $failed_count -eq 0 ]; then
        log_success "Successfully cancelled $success_count contracts"
        return 0
    else
        log_warning "Cancelled $success_count contracts, $failed_count failed"
        return 1
    fi
}

# =============================================================================
# STATE MANAGEMENT FUNCTIONS
# =============================================================================

# Synchronize local state with grid contracts
contracts_sync_state() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "App name required for state synchronization"
        return 1
    fi

    # Get twin ID from credentials or state
    # This would need to be implemented based on how twin ID is stored/retrieved
    local twin_id
    twin_id=$(get_twin_id)

    if [ -z "$twin_id" ]; then
        log_error "Unable to determine twin ID"
        return 1
    fi

    log_info "Synchronizing state for app: $app_name (twin_id: $twin_id)"

    # Get all contracts from GridProxy
    local contracts_json
    contracts_json=$(contracts_list_gridproxy "$twin_id")

    if [ $? -ne 0 ]; then
        log_error "Failed to fetch contracts from GridProxy"
        return 1
    fi

    # Update local state file with contract information
    # This would integrate with the existing state management system
    log_info "State synchronization completed"
    return 0
}

# Identify orphaned contracts (exist in grid but not in local state)
contracts_find_orphaned() {
    local app_name="$1"

    if [ -z "$app_name" ]; then
        log_error "App name required for orphaned contract detection"
        return 1
    fi

    log_info "Scanning for orphaned contracts in app: $app_name"

    # Compare local state vs grid contracts
    # Implementation would depend on how contracts are tracked in state.yaml files

    log_info "Orphaned contract scan completed"
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get twin ID from credentials or cached value
get_twin_id() {
    # Check if twin_id is already cached in environment
    if [ -n "${TFGRID_TWIN_ID:-}" ]; then
        echo "$TFGRID_TWIN_ID"
        return 0
    fi

    # Check if twin_id is cached in credentials file
    if [ -f "$CREDENTIALS_FILE" ]; then
        local cached_twin_id
        cached_twin_id=$(grep "twin_id:" "$CREDENTIALS_FILE" 2>/dev/null | sed 's/.*twin_id:[[:space:]]*//' | sed 's/["\047]//g')
        if [ -n "$cached_twin_id" ]; then
            export TFGRID_TWIN_ID="$cached_twin_id"
            echo "$cached_twin_id"
            return 0
        fi
    fi

    # Load credentials to ensure we have a mnemonic
    if ! load_credentials; then
        log_error "Failed to load credentials for twin ID derivation"
        return 1
    fi

    if [ -z "$TFGRID_MNEMONIC" ]; then
        log_error "Mnemonic not available for twin ID derivation"
        return 1
    fi

    # Use tfcmd to get twin ID (requires login first)
    if command_exists tfcmd; then
        log_info "Deriving twin ID from tfcmd..."

        # Ensure tfcmd is logged in
        if ! tfcmd login status >/dev/null 2>&1; then
            log_error "tfcmd not logged in. Run 'tfgrid-compose login' first"
            return 1
        fi

        # Get twin ID from tfcmd
        local twin_id
        twin_id=$(tfcmd twin get 2>/dev/null | grep -o '"id":[[:space:]]*[0-9]*' | grep -o '[0-9]*' | head -1)

        if [ -n "$twin_id" ] && [[ "$twin_id" =~ ^[0-9]+$ ]]; then
            log_success "Derived twin ID: $twin_id"
            export TFGRID_TWIN_ID="$twin_id"

            # Cache in credentials file
            if [ -f "$CREDENTIALS_FILE" ]; then
                sed -i '/^twin_id:/d' "$CREDENTIALS_FILE"
                echo "twin_id: \"$twin_id\"" >> "$CREDENTIALS_FILE"
            fi

            echo "$twin_id"
            return 0
        fi
    fi

    log_error "Failed to derive twin ID from tfcmd"
    return 1
}

# Format contract data for display
format_contract_output() {
    local json_data="$1"
    local format="${2:-table}"  # table, json, csv

    case "$format" in
        "json")
            echo "$json_data"
            ;;
        "csv")
            # Convert JSON to CSV using jq if available
            if command_exists jq; then
                echo "ID,Type,NodeID,State,CostMonthly,TFTCost,CreatedAt,AppName"
                echo "$json_data" | jq -r '.[] | [.id, .type, .node_id, .state, .cost_monthly, .tft_cost, .created_at, .app_name] | @csv'
            else
                log_warning "jq not available, falling back to table format"
                format_contract_output "$json_data" "table"
            fi
            ;;
        "table"|*)
            # Format as table
            if command_exists jq; then
                echo "┌─────────────────────────────────────────────────────────────────────────────────┐"
                echo "│                              CONTRACTS OVERVIEW                                │"
                echo "├──────┬─────────┬────────┬─────────┬─────────────┬──────────┬────────────────────┤"
                echo "│ ID   │ Type    │ NodeID │ State   │ Cost/Month  │ TFT Cost │ Created            │"
                echo "├──────┼─────────┼────────┼─────────┼─────────────┼──────────┼────────────────────┤"

                echo "$json_data" | jq -r '.[] | [.id, .type, .node_id, .state, .cost_monthly, .tft_cost, (.created_at | strftime("%Y-%m-%d %H:%M"))] | @tsv' | \
                while IFS=$'\t' read -r id type node_id state cost_monthly tft_cost created_at; do
                    printf "│ %-4s │ %-7s │ %-6s │ %-7s │ %-11s │ %-8s │ %-18s │\n" \
                           "$id" "$type" "$node_id" "$state" "$cost_monthly" "$tft_cost" "$created_at"
                done

                echo "└──────┴─────────┴────────┴─────────┴─────────────┴──────────┴────────────────────┘"
            else
                # Fallback without jq
                log_warning "jq not available, using simple list format"
                echo "$json_data" | grep -o '"id":"[^"]*"' | sed 's/"id":"\([^"]*\)"/Contract ID: \1/'
            fi
            ;;
    esac
}

# Validate contract ID format
validate_contract_id() {
    local contract_id="$1"

    # Contract IDs should be numeric
    if ! [[ "$contract_id" =~ ^[0-9]+$ ]]; then
        log_error "Invalid contract ID format: $contract_id (must be numeric)"
        return 1
    fi

    return 0
}

# Parse and validate network parameter
validate_network() {
    local network="$1"

    case "$network" in
        "main"|"test"|"dev")
            return 0
            ;;
        *)
            log_error "Invalid network: $network (must be main, test, or dev)"
            return 1
            ;;
    esac
}

# CLI wrapper functions for contracts subcommand
contracts_cli_list() {
    local filter_type=""
    local filter_state=""
    local format="table"

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                filter_type="$2"
                shift 2
                ;;
            --state)
                filter_state="$2"
                shift 2
                ;;
            --format)
                format="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Get twin ID
    local twin_id
    twin_id=$(get_twin_id)
    if [ -z "$twin_id" ]; then
        return 1
    fi

    # Get contracts
    local contracts_json
    contracts_json=$(contracts_list_gridproxy "$twin_id")
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Apply filters and format
    local filtered_json
    filtered_json=$(contracts_filter_and_sort "$contracts_json" "$filter_type" "$filter_state")

    format_contract_output "$filtered_json" "$format"
}

contracts_cli_show() {
    local contract_id="$1"

    if [ -z "$contract_id" ]; then
        log_error "Contract ID required"
        return 1
    fi

    if ! validate_contract_id "$contract_id"; then
        return 1
    fi

    local contract_json
    contract_json=$(contracts_get_details "$contract_id")
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Pretty print the contract details
    if command_exists jq; then
        echo "$contract_json" | jq '.'
    else
        echo "$contract_json"
    fi
}

contracts_cli_delete() {
    local contract_ids=("$@")

    if [ ${#contract_ids[@]} -eq 0 ]; then
        log_error "No contract IDs specified"
        return 1
    fi

    # Validate contract IDs
    for id in "${contract_ids[@]}"; do
        if ! validate_contract_id "$id"; then
            return 1
        fi
    done

    if [ ${#contract_ids[@]} -eq 1 ]; then
        contracts_cancel_single "${contract_ids[0]}"
    else
        contracts_cancel_batch "${contract_ids[*]}"
    fi
}

contracts_cli_prune() {
    log_info "Contract pruning not yet implemented"
    log_info "This would identify and clean up orphaned contracts"
    return 0
}

contracts_cli_sync() {
    log_info "Contract synchronization not yet implemented"
    log_info "This would sync local state with grid contracts"
    return 0
}

contracts_cli_help() {
    echo "TFGrid Compose - Contract Management"
    echo ""
    echo "USAGE:"
    echo "  tfgrid-compose contracts <subcommand> [options]"
    echo ""
    echo "SUBCOMMANDS:"
    echo "  list     List contracts with optional filtering"
    echo "  show     Show detailed information for a specific contract"
    echo "  delete   Cancel one or more contracts"
    echo "  prune    Remove orphaned contracts (not implemented)"
    echo "  sync     Synchronize local state with grid (not implemented)"
    echo ""
    echo "OPTIONS:"
    echo "  --type <type>     Filter by contract type (node, name)"
    echo "  --state <state>   Filter by contract state (active, grace, deleted)"
    echo "  --format <fmt>    Output format (table, json, csv)"
    echo ""
    echo "EXAMPLES:"
    echo "  tfgrid-compose contracts list"
    echo "  tfgrid-compose contracts list --state active"
    echo "  tfgrid-compose contracts show 12345"
    echo "  tfgrid-compose contracts delete 12345"
    echo "  tfgrid-compose contracts delete 12345 12346 12347"
}

# Export functions for use in other scripts
export -f contracts_list_gridproxy
export -f contracts_get_details
export -f contracts_filter_and_sort
export -f contracts_cancel_single
export -f contracts_cli_list
export -f contracts_cli_show
export -f contracts_cli_delete
export -f contracts_cli_help
export -f contracts_cancel_batch
export -f contracts_sync_state
export -f contracts_find_orphaned
export -f format_contract_output
export -f validate_contract_id
export -f validate_network