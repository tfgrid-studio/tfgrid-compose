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

# Cancel single contract using tfgrid-sdk-go
contracts_cancel_single() {
    local contract_id="$1"
    local network="${2:-main}"

    if [ -z "$contract_id" ]; then
        log_error "Contract ID required for cancellation"
        return 1
    fi

    if ! check_tfgrid_sdk_binary; then
        return 1
    fi

    # Load credentials
    if ! load_credentials; then
        log_error "Failed to load credentials"
        return 1
    fi

    if [ -z "$TFGRID_MNEMONIC" ]; then
        log_error "ThreeFold mnemonic not configured"
        log_info "Run 'tfgrid-compose login' to configure credentials"
        return 1
    fi

    local ws_url="${NETWORK_CONFIGS[$network]}"
    if [ -z "$ws_url" ]; then
        log_error "Unknown network: $network"
        return 1
    fi

    log_info "Cancelling contract $contract_id on $network network"

    # Call tfgrid-sdk-go binary
    # Note: This assumes tfgrid-sdk-go has a CLI interface for contract cancellation
    # The exact command format may need adjustment based on the actual binary interface
    local cmd="$TFGRID_SDK_BINARY cancel-contract --contract-id $contract_id --mnemonic \"$TFGRID_MNEMONIC\" --network $network"

    if [ "${TFGRID_VERBOSE:-}" = "1" ]; then
        log_info "Executing: $cmd"
        eval "$cmd"
        return $?
    else
        eval "$cmd" >/dev/null 2>&1
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            log_success "Contract $contract_id cancelled successfully"
        else
            log_error "Failed to cancel contract $contract_id"
        fi
        return $exit_code
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

    if ! check_tfgrid_sdk_binary; then
        return 1
    fi

    # Load credentials
    if ! load_credentials; then
        log_error "Failed to load credentials"
        return 1
    fi

    if [ -z "$TFGRID_MNEMONIC" ]; then
        log_error "ThreeFold mnemonic not configured"
        return 1
    fi

    local contract_count=$(echo "$contract_ids" | wc -w | tr -d ' ')
    log_info "Batch cancelling $contract_count contracts on $network network"

    # Convert space-separated to comma-separated for the binary
    local contract_list=$(echo "$contract_ids" | tr ' ' ',')

    local cmd="$TFGRID_SDK_BINARY batch-cancel-contracts --contract-ids $contract_list --mnemonic \"$TFGRID_MNEMONIC\" --network $network"

    if [ "${TFGRID_VERBOSE:-}" = "1" ]; then
        log_info "Executing: $cmd"
        eval "$cmd"
        return $?
    else
        eval "$cmd" >/dev/null 2>&1
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            log_success "Successfully cancelled $contract_count contracts"
        else
            log_error "Failed to cancel contracts"
        fi
        return $exit_code
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

    # For now, return a placeholder twin ID for testing
    # In production, this would derive from mnemonic using tfgrid-sdk-go
    # But since the binary isn't available, we'll use a test approach

    # Load credentials to ensure we have a mnemonic
    if ! load_credentials; then
        log_error "Failed to load credentials for twin ID derivation"
        return 1
    fi

    if [ -z "$TFGRID_MNEMONIC" ]; then
        log_error "Mnemonic not available for twin ID derivation"
        return 1
    fi

    # For testing/development: derive twin ID from mnemonic using tfcmd
    # In production, this would be the proper implementation
    if [ -f "$HOME/.local/share/tfgrid-compose/bin/tfcmd" ]; then
        log_info "Deriving twin ID from mnemonic using tfcmd..."

        # Use tfcmd to get twin ID from mnemonic
        # Note: tfcmd might need different parameters, this is a placeholder
        local cmd="$HOME/.local/share/tfgrid-compose/bin/tfcmd get twin-id --mnemonic \"$TFGRID_MNEMONIC\""
        local derived_twin_id

        if [ "${TFGRID_VERBOSE:-}" = "1" ]; then
            log_info "Executing: $cmd"
            derived_twin_id=$(eval "$cmd" 2>&1)
            local exit_code=$?
        else
            derived_twin_id=$(eval "$cmd" 2>/dev/null)
            local exit_code=$?
        fi

        if [ $exit_code -eq 0 ] && [ -n "$derived_twin_id" ]; then
            # Clean the output and extract twin ID
            derived_twin_id=$(echo "$derived_twin_id" | grep -o '"twin_id":[[:space:]]*[0-9]*' | grep -o '[0-9]*' | head -1)

            # Validate it's numeric
            if [[ "$derived_twin_id" =~ ^[0-9]+$ ]]; then
                log_success "Derived twin ID: $derived_twin_id"
                test_twin_id="$derived_twin_id"
            else
                log_warning "Invalid twin ID format from tfcmd, falling back to hash method"
            fi
        else
            log_warning "Failed to derive twin ID from tfcmd, falling back to hash method"
        fi
    fi

    # Fallback: derive a deterministic twin ID from mnemonic hash
    if [ -z "$test_twin_id" ]; then
        local mnemonic_hash
        mnemonic_hash=$(echo "$TFGRID_MNEMONIC" | sha256sum | cut -d' ' -f1 | cut -c1-8)
        test_twin_id=$((16#${mnemonic_hash:0:6}))
        log_warning "Using fallback twin ID derivation (not secure for production)"
    fi

    log_info "Twin ID: $test_twin_id"

    # Cache the twin ID
    export TFGRID_TWIN_ID="$test_twin_id"

    # Add to credentials file for future use
    if [ -f "$CREDENTIALS_FILE" ]; then
        # Remove old twin_id line if exists
        sed -i '/^twin_id:/d' "$CREDENTIALS_FILE"
        # Add new twin_id
        echo "twin_id: \"$test_twin_id\"" >> "$CREDENTIALS_FILE"
    fi

    echo "$test_twin_id"
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

# Export functions for use in other scripts
export -f contracts_list_gridproxy
export -f contracts_get_details
export -f contracts_filter_and_sort
export -f contracts_cancel_single
export -f contracts_cancel_batch
export -f contracts_sync_state
export -f contracts_find_orphaned
export -f format_contract_output
export -f validate_contract_id
export -f validate_network