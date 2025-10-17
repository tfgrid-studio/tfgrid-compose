#!/usr/bin/env bash
# Node Selector - GridProxy API integration
# Auto-selects best available node for deployment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

GRIDPROXY_URL="https://gridproxy.grid.tf"

# Select best node matching requirements
select_best_node() {
    local cpu=$1
    local mem_mb=$2
    local disk_gb=$3
    local network=${4:-main}
    
    log_info "Querying ThreeFold Grid for available nodes..."
    log_info "Requirements: ${cpu} CPU, ${mem_mb}MB RAM, ${disk_gb}GB disk"
    echo ""
    
    # Convert to bytes for API
    local mru=$((mem_mb * 1024 * 1024))
    local sru=$((disk_gb * 1024 * 1024 * 1024))
    
    # Query GridProxy
    local api_url="${GRIDPROXY_URL}/nodes?status=up&free_mru=${mru}&free_sru=${sru}&size=50"
    local response=$(curl -s "$api_url")
    
    if [ $? -ne 0 ]; then
        log_error "Failed to query GridProxy API"
        echo ""
        echo "Please check your internet connection and try again."
        return 1
    fi
    
    # Parse response with jq
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        echo ""
        echo "Install jq:"
        echo "  Ubuntu/Debian: sudo apt install jq"
        echo "  MacOS: brew install jq"
        return 1
    fi
    
    # Count available nodes
    local node_count=$(echo "$response" | jq -r 'length')
    
    if [ "$node_count" -eq 0 ]; then
        log_error "No nodes found matching requirements"
        echo ""
        echo "Try:"
        echo "  - Reducing resource requirements"
        echo "  - Checking node availability: https://dashboard.grid.tf"
        echo "  - Specifying a node manually: --node <id>"
        return 1
    fi
    
    log_success "Found $node_count nodes matching requirements"
    echo ""
    
    # Filter and select best node (highest uptime, healthy, non-dedicated)
    local selected_node=$(echo "$response" | jq -r '
        [.[] | select(.healthy == true and .dedicated == false)] |
        sort_by(.uptime) | reverse | .[0] |
        {id: .nodeId, country: .country, farm: .farmName, uptime: .uptime, city: .city}')
    
    if [ "$selected_node" = "null" ] || [ -z "$selected_node" ]; then
        log_error "No suitable nodes found (all dedicated or unhealthy)"
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
    echo ""
    
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
        echo ""
        return 0
    else
        log_error "Node $node_id is not available (status: $status)"
        echo ""
        echo "Try:"
        echo "  - Choose a different node"
        echo "  - Browse available nodes: https://dashboard.grid.tf"
        echo "  - Use auto-selection (remove --node flag)"
        return 1
    fi
}

# Query available nodes (for interactive mode)
query_gridproxy() {
    local cpu=$1
    local mem_mb=$2
    local disk_gb=$3
    
    local mru=$((mem_mb * 1024 * 1024))
    local sru=$((disk_gb * 1024 * 1024 * 1024))
    
    curl -s "${GRIDPROXY_URL}/nodes?status=up&free_mru=${mru}&free_sru=${sru}&size=50"
}

# Show available nodes (formatted list)
show_available_nodes() {
    local cpu=$1
    local mem_mb=$2
    local disk_gb=$3
    
    log_info "Querying available nodes..."
    
    local nodes=$(query_gridproxy "$cpu" "$mem_mb" "$disk_gb")
    local count=$(echo "$nodes" | jq -r 'length')
    
    if [ "$count" -eq 0 ]; then
        log_error "No nodes found with those specs"
        return 1
    fi
    
    echo ""
    echo "Available nodes with $cpu CPU, ${mem_mb}MB RAM, ${disk_gb}GB disk:"
    echo ""
    
    # Show top 10 nodes with formatted output
    echo "$nodes" | jq -r '
        [.[] | select(.healthy == true and .dedicated == false)] |
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
