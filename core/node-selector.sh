#!/usr/bin/env bash
# Node Selector - GridProxy API integration
# Auto-selects best available node for deployment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

GRIDPROXY_URL="https://gridproxy.grid.tf"

# Load configuration from config file
load_node_filter_config() {
    local config_file="$HOME/.config/tfgrid-compose/config.yaml"

    # Initialize defaults
    BLACKLIST_NODES=""
    BLACKLIST_FARMS=""
    WHITELIST_FARMS=""
    MAX_CPU_USAGE=""
    MAX_DISK_USAGE=""
    MIN_UPTIME_DAYS=""

    if [ -f "$config_file" ]; then
        # Parse YAML config (simple key=value extraction)
        while IFS=':' read -r key value; do
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)

            case "$key" in
                blacklist_nodes) BLACKLIST_NODES="$value" ;;
                blacklist_farms) BLACKLIST_FARMS="$value" ;;
                whitelist_farms) WHITELIST_FARMS="$value" ;;
                whitelist_nodes) WHITELIST_NODES="$value" ;;
                max_cpu_usage) MAX_CPU_USAGE="$value" ;;
                max_disk_usage) MAX_DISK_USAGE="$value" ;;
                min_uptime_days) MIN_UPTIME_DAYS="$value" ;;
            esac
        done < <(grep -E "^(blacklist_nodes|blacklist_farms|whitelist_farms|whitelist_nodes|max_cpu_usage|max_disk_usage|min_uptime_days):" "$config_file" 2>/dev/null || true)
    fi

    # Load environment variables if set
    BLACKLIST_NODES="${CUSTOM_BLACKLIST_NODES:-$BLACKLIST_NODES}"
    BLACKLIST_FARMS="${CUSTOM_BLACKLIST_FARMS:-$BLACKLIST_FARMS}"
    WHITELIST_FARMS="${CUSTOM_WHITELIST_FARMS:-$WHITELIST_FARMS}"
    WHITELIST_NODES="${CUSTOM_WHITELIST_NODES:-$WHITELIST_NODES}"
    MAX_CPU_USAGE="${CUSTOM_MAX_CPU_USAGE:-$MAX_CPU_USAGE}"
    MAX_DISK_USAGE="${CUSTOM_MAX_DISK_USAGE:-$MAX_DISK_USAGE}"
    MIN_UPTIME_DAYS="${CUSTOM_MIN_UPTIME_DAYS:-$MIN_UPTIME_DAYS}"
}

# Apply node filtering based on configuration and CLI overrides
apply_node_filters() {
    local nodes_json="$1"
    local cli_whitelist_nodes="${2:-}"
    local cli_blacklist_nodes="${3:-}"
    local cli_blacklist_farms="${4:-}"
    local cli_whitelist_farms="${5:-}"
    local cli_max_cpu="${6:-}"
    local cli_max_disk="${7:-}"
    local cli_min_uptime="${8:-}"

    # Use CLI overrides if provided, otherwise use config
    local whitelist_nodes="${cli_whitelist_nodes:-$WHITELIST_NODES}"
    local blacklist_nodes="${cli_blacklist_nodes:-$BLACKLIST_NODES}"
    local blacklist_farms="${cli_blacklist_farms:-$BLACKLIST_FARMS}"
    local whitelist_farms="${cli_whitelist_farms:-$WHITELIST_FARMS}"
    local max_cpu="${cli_max_cpu:-$MAX_CPU_USAGE}"
    local max_disk="${cli_max_disk:-$MAX_DISK_USAGE}"
    local min_uptime="${cli_min_uptime:-$MIN_UPTIME_DAYS}"

    # Convert comma-separated strings to arrays (filter out empty values)
    IFS=',' read -ra temp_nodes <<< "$whitelist_nodes"
    whitelist_nodes_array=()
    for node in "${temp_nodes[@]}"; do
        [[ -n "$node" ]] && whitelist_nodes_array+=("$node")
    done

    IFS=',' read -ra temp_nodes <<< "$blacklist_nodes"
    blacklist_nodes_array=()
    for node in "${temp_nodes[@]}"; do
        [[ -n "$node" ]] && blacklist_nodes_array+=("$node")
    done

    IFS=',' read -ra temp_farms <<< "$blacklist_farms"
    blacklist_farms_array=()
    for farm in "${temp_farms[@]}"; do
        [[ -n "$farm" ]] && blacklist_farms_array+=("$farm")
    done

    IFS=',' read -ra temp_whitelist <<< "$whitelist_farms"
    whitelist_farms_array=()
    for farm in "${temp_whitelist[@]}"; do
        [[ -n "$farm" ]] && whitelist_farms_array+=("$farm")
    done

    # Convert arrays to JSON for jq (handle empty arrays properly)
    local whitelist_nodes_json
    local blacklist_nodes_json
    local blacklist_farms_json
    local whitelist_farms_json

    if [ ${#whitelist_nodes_array[@]} -eq 0 ]; then
        whitelist_nodes_json="[]"
    else
        whitelist_nodes_json="$(printf '%s\n' "${whitelist_nodes_array[@]}" | jq -R . | jq -s .)"
    fi

    if [ ${#blacklist_nodes_array[@]} -eq 0 ]; then
        blacklist_nodes_json="[]"
    else
        blacklist_nodes_json="$(printf '%s\n' "${blacklist_nodes_array[@]}" | jq -R . | jq -s .)"
    fi

    if [ ${#blacklist_farms_array[@]} -eq 0 ]; then
        blacklist_farms_json="[]"
    else
        blacklist_farms_json="$(printf '%s\n' "${blacklist_farms_array[@]}" | jq -R . | jq -s .)"
    fi

    if [ ${#whitelist_farms_array[@]} -eq 0 ]; then
        whitelist_farms_json="[]"
    else
        whitelist_farms_json="$(printf '%s\n' "${whitelist_farms_array[@]}" | jq -R . | jq -s .)"
    fi

    # Apply filters using jq
    local filtered_nodes=$(echo "$nodes_json" | jq -r '
        [.[] | select(.healthy == true and .dedicated == false)] |
        map(
            # Apply whitelist logic (OR logic):
            # Node allowed if:
            # - No whitelist restrictions at all, OR
            # - Node is in whitelist_nodes, OR
            # - Node is in any of the whitelist_farms
            select(
                ($whitelist_nodes_array == [] and $whitelist_farms_array == []) or
                (.nodeId | tostring | IN($whitelist_nodes_array[] | tostring)) or
                (.farmName | IN($whitelist_farms_array[]))
            ) |

            # Apply blacklist filters (takes precedence - always overrides whitelist)
            select(
                (.nodeId | tostring | IN($blacklist_nodes_array[] | tostring)) | not
            ) |
            select(
                (.farmName | IN($blacklist_farms_array[])) | not
            ) |

            # Apply health thresholds
            select(
                ($max_cpu == "" or $max_cpu == null) or
                ((.used_resources.cru / (.total_resources.cru | tostring | tonumber)) * 100 | floor) <= ($max_cpu | tonumber)
            ) |
            select(
                ($max_disk == "" or $max_disk == null) or
                ((.used_resources.sru / (.total_resources.sru | tostring | tonumber)) * 100 | floor) <= ($max_disk | tonumber)
            ) |
            select(
                ($min_uptime == "" or $min_uptime == null) or
                (.uptime / 86400 | floor) >= ($min_uptime | tonumber)
            )
        )
    ' --argjson whitelist_nodes_array "$whitelist_nodes_json" \
      --argjson blacklist_nodes_array "$blacklist_nodes_json" \
      --argjson blacklist_farms_array "$blacklist_farms_json" \
      --argjson whitelist_farms_array "$whitelist_farms_json" \
      --arg max_cpu "$max_cpu" \
      --arg max_disk "$max_disk" \
      --arg min_uptime "$min_uptime")

    echo "$filtered_nodes"
}

# Select best node matching requirements
select_best_node() {
    local cpu=$1
    local mem_mb=$2
    local disk_gb=$3
    local network=${4:-main}
    local cli_blacklist_nodes="${5:-}"
    local cli_blacklist_farms="${6:-}"
    local cli_whitelist_farms="${7:-}"
    local cli_max_cpu="${8:-}"
    local cli_max_disk="${9:-}"
    local cli_min_uptime="${10:-}"

    log_info "Querying ThreeFold Grid for available nodes..."
    log_info "Requirements: ${cpu} CPU, ${mem_mb}MB RAM, ${disk_gb}GB disk"
    echo "" >&2

    # Load configuration
    load_node_filter_config

    # Convert to bytes for API
    local mru=$((mem_mb * 1024 * 1024))
    local sru=$((disk_gb * 1024 * 1024 * 1024))

    # Query GridProxy
    local api_url="${GRIDPROXY_URL}/nodes?status=up&free_mru=${mru}&free_sru=${sru}&size=50"
    local response=$(curl -s "$api_url")

    if [ $? -ne 0 ]; then
        log_error "Failed to query GridProxy API"
        echo "" >&2
        echo "Please check your internet connection and try again." >&2
        return 1
    fi

    # Parse response with jq
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        echo "" >&2
        echo "Install jq:" >&2
        echo "  Ubuntu/Debian: sudo apt install jq" >&2
        echo "  MacOS: brew install jq" >&2
        return 1
    fi

    # Count available nodes
    local node_count=$(echo "$response" | jq -r 'length')

    if [ "$node_count" -eq 0 ]; then
        log_error "No nodes found matching requirements"
        echo "" >&2
        echo "Try:" >&2
        echo "  - Reducing resource requirements" >&2
        echo "  - Checking node availability: https://dashboard.grid.tf" >&2
        echo "  - Specifying a node manually: --node <id>" >&2
        return 1
    fi

    log_success "Found $node_count nodes matching requirements"

    # Apply filtering
    local filtered_nodes=$(apply_node_filters "$response" "$cli_blacklist_nodes" "$cli_blacklist_farms" "$cli_whitelist_farms" "$cli_max_cpu" "$cli_max_disk" "$cli_min_uptime")
    local filtered_count=$(echo "$filtered_nodes" | jq -r 'length')

    if [ "$filtered_count" -eq 0 ]; then
        log_error "No nodes found after applying filters"
        echo "" >&2
        echo "Try:" >&2
        echo "  - Adjusting filter criteria" >&2
        echo "  - Checking filter configuration: ~/.config/tfgrid-compose/config.yaml" >&2
        echo "  - Using --node to specify manually" >&2
        return 1
    fi

    log_success "Found $filtered_count nodes after filtering"
    echo "" >&2

    # Filter and select best node (highest uptime from filtered list)
    local selected_node=$(echo "$filtered_nodes" | jq -r '
        sort_by(.uptime) | reverse | .[0] |
        {id: .nodeId, country: .country, farm: .farmName, uptime: .uptime, city: .city}')

    if [ "$selected_node" = "null" ] || [ -z "$selected_node" ]; then
        log_error "No suitable nodes found after filtering"
        return 1
    fi

    local node_id=$(echo "$selected_node" | jq -r '.id')
    local country=$(echo "$selected_node" | jq -r '.country')
    local city=$(echo "$selected_node" | jq -r '.city // "Unknown"')
    local farm=$(echo "$selected_node" | jq -r '.farm')
    local uptime=$(echo "$selected_node" | jq -r '.uptime')
    local uptime_days=$(awk "BEGIN {printf \"%.0f\", $uptime / 86400}")

    log_info "Selected node: $node_id"
    log_info "Location: $country ($city)"
    log_info "Farm: $farm"
    log_info "Uptime: $uptime_days days"
    echo "" >&2

    echo "$node_id"
}

# Verify node exists and is online
verify_node_exists() {
    local node_id=$1
    
    log_info "Verifying node $node_id..."
    
    local node=$(curl -s "${GRIDPROXY_URL}/nodes?node_id=${node_id}")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to query GridProxy API"
        return 1
    fi
    
    local status=$(echo "$node" | jq -r '.[0].status // "unknown"')
    
    if [ "$status" = "up" ]; then
        local country=$(echo "$node" | jq -r '.[0].country // "Unknown"')
        local farm=$(echo "$node" | jq -r '.[0].farmName // "Unknown"')
        log_success "Node $node_id is online ($country, $farm)"
        echo "" >&2
        return 0
    else
        log_error "Node $node_id is not available (status: $status)"
        echo "" >&2
        echo "Try:" >&2
        echo "  - Choose a different node" >&2
        echo "  - Browse available nodes: https://dashboard.grid.tf" >&2
        echo "  - Use auto-selection (remove --node flag)" >&2
        return 1
    fi
}

# Query available nodes (for interactive mode)
query_gridproxy() {
    local cpu=$1
    local mem_mb=$2
    local disk_gb=$3
    local cli_blacklist_nodes="${4:-}"
    local cli_blacklist_farms="${5:-}"
    local cli_whitelist_farms="${6:-}"
    local cli_max_cpu="${7:-}"
    local cli_max_disk="${8:-}"
    local cli_min_uptime="${9:-}"

    local mru=$((mem_mb * 1024 * 1024))
    local sru=$((disk_gb * 1024 * 1024 * 1024))

    local response=$(curl -s "${GRIDPROXY_URL}/nodes?status=up&free_mru=${mru}&free_sru=${sru}&size=50")

    # Load config and apply filters
    load_node_filter_config
    local filtered_response=$(apply_node_filters "$response" "$cli_blacklist_nodes" "$cli_blacklist_farms" "$cli_whitelist_farms" "$cli_max_cpu" "$cli_max_disk" "$cli_min_uptime")

    echo "$filtered_response"
}

# Show available nodes (formatted list)
show_available_nodes() {
    local cpu=$1
    local mem_mb=$2
    local disk_gb=$3
    local cli_blacklist_nodes="${4:-}"
    local cli_blacklist_farms="${5:-}"
    local cli_whitelist_farms="${6:-}"
    local cli_max_cpu="${7:-}"
    local cli_max_disk="${8:-}"
    local cli_min_uptime="${9:-}"

    log_info "Querying available nodes..."

    local nodes=$(query_gridproxy "$cpu" "$mem_mb" "$disk_gb" "$cli_blacklist_nodes" "$cli_blacklist_farms" "$cli_whitelist_farms" "$cli_max_cpu" "$cli_max_disk" "$cli_min_uptime")
    local count=$(echo "$nodes" | jq -r 'length')

    if [ "$count" -eq 0 ]; then
        log_error "No nodes found with those specs and filters"
        return 1
    fi

    echo ""
    echo "Available nodes with $cpu CPU, ${mem_mb}MB RAM, ${disk_gb}GB disk:"
    echo ""

    # Show top 10 nodes with formatted output
    echo "$nodes" | jq -r '
        sort_by(.uptime) | reverse | .[:10] | to_entries[] |
        "  \(.key + 1). Node \(.value.nodeId) - \(.value.country) - \(.value.farmName) - \((.value.uptime / 86400 | floor))d uptime"
    '

    if [ "$count" -gt 10 ]; then
        echo "  ... and $((count - 10)) more"
    fi
    echo ""

    # Return node list for selection
    echo "$nodes"
}

# Get node ID from list selection
get_node_from_list() {
    local selection=$1
    local nodes=$2
    
    # Extract node ID from selected index (1-based)
    echo "$nodes" | jq -r "
        [.[] | select(.healthy == true and .dedicated == false)] |
        sort_by(.uptime) | reverse |
        .[$(($selection - 1))].nodeId
    "
}
