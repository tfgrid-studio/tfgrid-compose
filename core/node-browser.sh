#!/usr/bin/env bash
# Interactive Node Browser
# Provides interactive exploration of available nodes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/node-selector.sh"

GRIDPROXY_URL="https://gridproxy.grid.tf"

# Favorites file
FAVORITES_FILE="$HOME/.config/tfgrid-compose/node-favorites"

# Ensure favorites file exists
ensure_favorites_file() {
    mkdir -p "$(dirname "$FAVORITES_FILE")"
    touch "$FAVORITES_FILE"
}

# Add node to favorites
add_favorite() {
    local node_id="$1"
    # Trim whitespace from node_id
    node_id=$(echo "$node_id" | xargs)
    ensure_favorites_file

    if grep -q "^${node_id}$" "$FAVORITES_FILE"; then
        log_info "Node $node_id is already in favorites"
    else
        echo "$node_id" >> "$FAVORITES_FILE"
        log_success "Added node $node_id to favorites"
    fi
}

# Remove node from favorites
remove_favorite() {
    local node_id="$1"
    ensure_favorites_file

    if grep -q "^${node_id}$" "$FAVORITES_FILE"; then
        sed -i "/^${node_id}$/d" "$FAVORITES_FILE"
        log_success "Removed node $node_id from favorites"
    else
        log_info "Node $node_id is not in favorites"
    fi
}

# Check if node is favorite
is_favorite() {
    local node_id="$1"
    ensure_favorites_file
    grep -q "^${node_id}$" "$FAVORITES_FILE"
}

# Get favorites list
get_favorites() {
    ensure_favorites_file
    cat "$FAVORITES_FILE" 2>/dev/null || true
}

# Display node table header
show_table_header() {
    echo ""
    echo "🔍 ThreeFold Node Browser"
    echo ""
    printf "%-6s %-20s %-15s %-6s %-6s %-6s %-6s %-8s %-10s\n" "ID" "Farm" "Location" "CPU" "RAM" "Disk" "IPv4" "Load" "Uptime"
    echo "────────────────────────────────────────────────────────────────────────────────"
}

# Display single node in table format
show_node_row() {
    local node="$1"
    local is_fav=""

    local node_id=$(echo "$node" | jq -r '.nodeId')
    local farm=$(echo "$node" | jq -r '.farmName // "Unknown"' | cut -c1-20)
    local country=$(echo "$node" | jq -r '.country // "Unknown"')
    local city=$(echo "$node" | jq -r '.city // ""')
    local location="$country"
    [ -n "$city" ] && location="$city, $country"
    location=$(echo "$location" | cut -c1-15)

    local total_cpu=$(echo "$node" | jq -r '.total_resources.cru // 0')
    local used_cpu=$(echo "$node" | jq -r '.used_resources.cru // 0')
    local cpu_load=$(( used_cpu * 100 / (total_cpu > 0 ? total_cpu : 1) ))

    local total_ram_gb=$(( $(echo "$node" | jq -r '.total_resources.mru // 0') / 1024 / 1024 / 1024 ))
    local total_disk_tb=$(( $(echo "$node" | jq -r '.total_resources.sru // 0') / 1024 / 1024 / 1024 / 1024 ))

    local ipv4=$(echo "$node" | jq -r 'if .public_config.ipv4 | length > 0 then "Yes" else "No" end')
    local uptime_days=$(( $(echo "$node" | jq -r '.uptime // 0') / 86400 ))

    if is_favorite "$node_id"; then
        is_fav="★"
    fi

    printf "%-6s %-20s %-15s %-6s %-6s %-6s %-6s %-8s %-10s\n" \
        "${node_id}${is_fav}" "$farm" "$location" "$total_cpu" "${total_ram_gb}G" "${total_disk_tb}T" "$ipv4" "${cpu_load}%" "${uptime_days}d"
}

# Show detailed node information
show_node_details() {
    local node="$1"
    local node_id=$(echo "$node" | jq -r '.nodeId')

    echo ""
    echo "📋 Node Details: $node_id"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    local farm=$(echo "$node" | jq -r '.farmName // "Unknown"')
    local country=$(echo "$node" | jq -r '.country // "Unknown"')
    local city=$(echo "$node" | jq -r '.city // "Unknown"')
    local healthy=$(echo "$node" | jq -r '.healthy // false')
    local dedicated=$(echo "$node" | jq -r '.dedicated // false')

    echo "Farm: $farm"
    echo "Location: $city, $country"
    echo "Status: $([ "$healthy" = "true" ] && echo "Healthy" || echo "Unhealthy")"
    echo "Type: $([ "$dedicated" = "true" ] && echo "Dedicated" || echo "Community")"

    # Resources
    local total_cpu=$(echo "$node" | jq -r '.total_resources.cru // 0')
    local used_cpu=$(echo "$node" | jq -r '.used_resources.cru // 0')
    local cpu_load=$(( used_cpu * 100 / (total_cpu > 0 ? total_cpu : 1) ))

    local total_ram_gb=$(( $(echo "$node" | jq -r '.total_resources.mru // 0') / 1024 / 1024 / 1024 ))
    local used_ram_gb=$(( $(echo "$node" | jq -r '.used_resources.mru // 0') / 1024 / 1024 / 1024 ))

    local total_disk_tb=$(( $(echo "$node" | jq -r '.total_resources.sru // 0') / 1024 / 1024 / 1024 / 1024 ))
    local used_disk_tb=$(( $(echo "$node" | jq -r '.used_resources.sru // 0') / 1024 / 1024 / 1024 / 1024 ))

    echo ""
    echo "Resources:"
    echo "  CPU: ${used_cpu}/${total_cpu} cores (${cpu_load}% used)"
    echo "  RAM: ${used_ram_gb}/${total_ram_gb} GB"
    echo "  Disk: ${used_disk_tb}/${total_disk_tb} TB"

    # Network
    local ipv4_count=$(echo "$node" | jq -r '.public_config.ipv4 | length')
    local ipv6_count=$(echo "$node" | jq -r '.public_config.ipv6 | length')

    echo ""
    echo "Network:"
    echo "  IPv4 addresses: $ipv4_count"
    echo "  IPv6 addresses: $ipv6_count"

    # Uptime
    local uptime_seconds=$(echo "$node" | jq -r '.uptime // 0')
    local uptime_days=$(( uptime_seconds / 86400 ))
    local uptime_hours=$(( (uptime_seconds % 86400) / 3600 ))

    echo ""
    echo "Uptime: ${uptime_days} days, ${uptime_hours} hours"

    # Favorite status
    echo ""
    if is_favorite "$node_id"; then
        echo "⭐ This node is in your favorites"
    else
        echo "☆ This node is not in your favorites"
    fi

    echo ""
    echo "Commands:"
    echo "  f) Toggle favorite"
    echo "  d) Deploy to this node"
    echo "  q) Back to list"
}

# Interactive node browser
interactive_browser() {
    local cpu="${1:-2}"
    local mem_mb="${2:-4096}"
    local disk_gb="${3:-50}"

    log_info "Starting interactive node browser..."
    log_info "Fetching available nodes..."

    # Get filtered nodes
    local nodes=$(query_gridproxy "$cpu" "$mem_mb" "$disk_gb")
    local node_count=$(echo "$nodes" | jq -r 'length')

    if [ "$node_count" -eq 0 ]; then
        log_error "No nodes found matching criteria"
        return 1
    fi

    log_success "Found $node_count nodes"

    # Convert to array for navigation
    local node_array=()
    while IFS= read -r node; do
        node_array+=("$node")
    done < <(echo "$nodes" | jq -c '.[]')

    # Page-based navigation variables
    local nodes_per_page=20
    local total_pages=$(( (node_count + nodes_per_page - 1) / nodes_per_page ))
    local current_page=0
    local current_index=0  # Selected node within current page
    local view_mode="list"  # list or details or input
    local input_mode=""     # For typing node IDs

    while true; do
        case "$view_mode" in
            "list")
                # Clear screen for clean display
                clear

                # Show table view
                show_table_header

                # Calculate page boundaries
                local start_idx=$((current_page * nodes_per_page))
                local end_idx=$((start_idx + nodes_per_page))
                [ $end_idx -gt $node_count ] && end_idx=$node_count

                # Show nodes for current page
                for ((i=start_idx; i<end_idx; i++)); do
                    local marker=""
                    if [ $i -eq $((start_idx + current_index)) ]; then
                        marker="→"
                    fi
                    echo -n "$marker"
                    show_node_row "${node_array[$i]}"
                done

                echo ""
                echo "Page $((current_page + 1)) of $total_pages (nodes $((start_idx + 1))-$end_idx of $node_count)"
                echo "Node $((start_idx + current_index + 1)) of $node_count selected"
                echo ""
                echo "Navigation: ↑/↓ page arrows, PageUp/PageDown (5 pages)"
                echo "Actions: Enter=details, /=jump to node, f=favorite, d=deploy, q=quit"
                echo ""
                read -rsn1 key

                case "$key" in
                    $'\x1b')  # Escape sequence
                        read -rsn2 -t 0.3 key2  # Longer timeout for arrow keys
                        case "$key2" in
                            "[A")  # Up arrow - Previous page
                                if [ $current_page -gt 0 ]; then
                                    current_page=$((current_page - 1))
                                    current_index=0  # Reset to first node on page
                                fi
                                ;;
                            "[B")  # Down arrow - Next page
                                if [ $current_page -lt $((total_pages - 1)) ]; then
                                    current_page=$((current_page + 1))
                                    current_index=0  # Reset to first node on page
                                fi
                                ;;
                            "[5")  # Page Up - Jump 5 pages back
                                current_page=$((current_page - 5))
                                if [ $current_page -lt 0 ]; then
                                    current_page=0
                                fi
                                current_index=0
                                ;;
                            "[6")  # Page Down - Jump 5 pages forward
                                current_page=$((current_page + 5))
                                if [ $current_page -ge $total_pages ]; then
                                    current_page=$((total_pages - 1))
                                fi
                                current_index=0
                                ;;
                        esac
                        ;;
                    "")  # Enter
                        view_mode="details"
                        ;;
                    "/")
                        view_mode="input"
                        input_mode=""
                        ;;
                    "f"|"F")
                        local selected_idx=$((start_idx + current_index))
                        local node_id=$(echo "${node_array[$selected_idx]}" | jq -r '.nodeId')
                        if is_favorite "$node_id"; then
                            remove_favorite "$node_id"
                        else
                            add_favorite "$node_id"
                        fi
                        ;;
                    "d"|"D")
                        local selected_idx=$((start_idx + current_index))
                        local node_id=$(echo "${node_array[$selected_idx]}" | jq -r '.nodeId')
                        echo ""
                        log_info "To deploy to node $node_id, run:"
                        echo "tfgrid-compose up <app> --node=$node_id"
                        echo ""
                        read -p "Press Enter to continue..."
                        ;;
                    "q"|"Q")
                        echo ""
                        log_info "Goodbye!"
                        return 0
                        ;;
                esac
                ;;

            "details")
                # Clear screen for clean display
                clear

                # Show detailed view
                local selected_idx=$((current_page * nodes_per_page + current_index))
                show_node_details "${node_array[$selected_idx]}"

                read -rsn1 key
                case "$key" in
                    "f"|"F")
                        local selected_idx=$((current_page * nodes_per_page + current_index))
                        local node_id=$(echo "${node_array[$selected_idx]}" | jq -r '.nodeId')
                        if is_favorite "$node_id"; then
                            remove_favorite "$node_id"
                        else
                            add_favorite "$node_id"
                        fi
                        ;;
                    "d"|"D")
                        local selected_idx=$((current_page * nodes_per_page + current_index))
                        local node_id=$(echo "${node_array[$selected_idx]}" | jq -r '.nodeId')
                        echo ""
                        log_info "To deploy to node $node_id, run:"
                        echo "tfgrid-compose up <app> --node=$node_id"
                        echo ""
                        read -p "Press Enter to continue..."
                        ;;
                    "q"|"Q"|""|$'\x1b')
                        view_mode="list"
                        ;;
                esac
                ;;

            "input")
                # Clear screen for clean display
                clear

                echo ""
                echo "🔍 Jump to Node"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                echo "Type a node ID number and press Enter to jump to that node."
                echo "Type part of a node ID to filter the list."
                echo "Press Escape or 'q' to cancel."
                echo ""
                echo -n "Node ID: $input_mode"

                # Read input character by character
                read -rsn1 key
                case "$key" in
                    $'\x1b'|q|Q)  # Escape or q to cancel
                        view_mode="list"
                        ;;
                    $'\x7f'|'\b')  # Backspace
                        input_mode="${input_mode%?}"
                        ;;
                    "")  # Enter - process input
                        if [ -n "$input_mode" ]; then
                            # Try to find node by exact ID first
                            local found_index=-1
                            for ((i=0; i<node_count; i++)); do
                                local node_id=$(echo "${node_array[$i]}" | jq -r '.nodeId')
                                if [ "$node_id" = "$input_mode" ]; then
                                    found_index=$i
                                    break
                                fi
                            done

                            if [ $found_index -ge 0 ]; then
                                # Found exact match - jump to that node
                                current_page=$((found_index / nodes_per_page))
                                current_index=$((found_index % nodes_per_page))
                                view_mode="list"
                            else
                                # No exact match - filter by partial match
                                local filtered_nodes=()
                                for ((i=0; i<node_count; i++)); do
                                    local node_id=$(echo "${node_array[$i]}" | jq -r '.nodeId')
                                    if [[ "$node_id" == *"$input_mode"* ]]; then
                                        filtered_nodes+=("$i")  # Store original index
                                    fi
                                done

                                if [ ${#filtered_nodes[@]} -eq 1 ]; then
                                    # Single match - jump to it
                                    local target_index=${filtered_nodes[0]}
                                    current_page=$((target_index / nodes_per_page))
                                    current_index=$((target_index % nodes_per_page))
                                    view_mode="list"
                                elif [ ${#filtered_nodes[@]} -gt 1 ]; then
                                    # Multiple matches - show first one
                                    local target_index=${filtered_nodes[0]}
                                    current_page=$((target_index / nodes_per_page))
                                    current_index=$((target_index % nodes_per_page))
                                    view_mode="list"
                                    echo ""
                                    log_info "Found ${#filtered_nodes[@]} nodes matching '$input_mode', showing first match"
                                    sleep 1
                                else
                                    # No matches
                                    echo ""
                                    log_error "No nodes found matching '$input_mode'"
                                    sleep 1
                                    view_mode="list"
                                fi
                            fi
                        else
                            view_mode="list"
                        fi
                        ;;
                    *)  # Regular character
                        # Only allow numbers for node IDs
                        if [[ "$key" =~ ^[0-9]$ ]]; then
                            input_mode="$input_mode$key"
                        fi
                        ;;
                esac
                ;;
        esac
    done
}

# Show favorites
show_favorites() {
    ensure_favorites_file
    local favorites=$(get_favorites)

    if [ -z "$favorites" ]; then
        log_info "No favorite nodes saved yet"
        log_info "Use 'f' in the browser to add favorites"
        return
    fi

    echo ""
    echo "⭐ Favorite Nodes"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-8s %-20s %-15s %-6s %-6s %-6s %-6s %-8s %-10s\n" "ID" "Farm" "Location" "CPU" "RAM" "Disk" "IPv4" "Load" "Uptime"
    echo "────────────────────────────────────────────────────────────────────────────────"

    # Temporary file to store all node data
    local tmp_online=$(mktemp)
    local tmp_offline=$(mktemp)
    trap "rm -f $tmp_online $tmp_offline" EXIT

    # Fetch each favorite node and store in temp files
    while IFS= read -r node_id; do
        node_id=$(echo "$node_id" | xargs)
        [ -z "$node_id" ] && continue

        # Validate node_id is numeric
        if ! [[ "$node_id" =~ ^[0-9]+$ ]]; then
            continue
        fi

        # Fetch node info
        local node_info=$(curl -s "${GRIDPROXY_URL}/nodes?node_id=${node_id}")
        if [ $? -eq 0 ] && [ -n "$node_info" ] && [ "$node_info" != "null" ] && [ "$node_info" != "[]" ]; then
            local node=$(echo "$node_info" | jq -r '.[0]')
            if [ "$node" != "null" ] && [ -n "$node" ]; then
                # Check if node is online
                local status=$(echo "$node" | jq -r '.status // "unknown"')
                if [ "$status" = "up" ]; then
                    # Store full node JSON for online nodes
                    echo "$node" >> "$tmp_online"
                else
                    # Store just ID for offline nodes
                    echo "$node_id" >> "$tmp_offline"
                fi
            else
                echo "$node_id" >> "$tmp_offline"
            fi
        else
            echo "$node_id" >> "$tmp_offline"
        fi
    done <<< "$favorites"

    # Display online nodes sorted by uptime (highest first)
    local online_count=0
    if [ -s "$tmp_online" ]; then
        # Sort by uptime and display
        jq -s 'sort_by(.uptime) | reverse | .[]' "$tmp_online" | while IFS= read -r node; do
            show_node_row "$node"
        done
        online_count=$(wc -l < "$tmp_online")
    fi

    # Display offline nodes
    local offline_count=0
    if [ -s "$tmp_offline" ]; then
        while IFS= read -r node_id; do
            [ -z "$node_id" ] && continue
            printf "%-8s %-20s %-15s %-6s %-6s %-6s %-6s %-8s %-10s\n" \
                "${node_id}🔴" "(offline)" "" "" "" "" "" "" ""
        done < "$tmp_offline"
        offline_count=$(wc -l < "$tmp_offline")
    fi

    echo ""
    echo "Total favorites: $((online_count + offline_count))"
    if [ $online_count -gt 0 ]; then
        echo "Online: ${online_count}  Offline: ${offline_count}"
    fi

    # Cleanup
    rm -f "$tmp_online" "$tmp_offline"
    echo ""
    echo "Legend: ID=Node ID, Farm=Farm Name, Location=City/Country, CPU=Total Cores"
    echo "        RAM=Total GB, Disk=Total TB, IPv4=IPv4 Available, Load=CPU Usage %, Uptime=Days"
    echo "        🔴 = Offline node"
}

# Main nodes command handler
nodes_command() {
    local subcommand="$1"
    shift || true  # Don't fail if no arguments to shift

    case "$subcommand" in
        "favorites"|"fav")
            show_favorites
            ;;
        "show")
            local node_id="$1"
            if [ -z "$node_id" ]; then
                log_error "Usage: tfgrid-compose nodes show <node-id>"
                exit 1
            fi

            log_info "Fetching details for node $node_id..."
            local node_info=$(curl -s "${GRIDPROXY_URL}/nodes?node_id=${node_id}")

            if [ $? -ne 0 ] || [ -z "$node_info" ]; then
                log_error "Failed to fetch node information"
                exit 1
            fi

            local node=$(echo "$node_info" | jq -r '.[0]')
            if [ "$node" = "null" ] || [ -z "$node" ]; then
                log_error "Node $node_id not found"
                exit 1
            fi

            show_node_details "$node"
            ;;
        "favorite"|"fav")
            local action="$1"
            local node_id="$2"

            case "$action" in
                "add")
                    if [ -z "$node_id" ]; then
                        log_error "Usage: tfgrid-compose nodes favorite add <node-id>"
                        exit 1
                    fi
                    add_favorite "$node_id"
                    ;;
                "remove"|"rm")
                    if [ -z "$node_id" ]; then
                        log_error "Usage: tfgrid-compose nodes favorite remove <node-id>"
                        exit 1
                    fi
                    remove_favorite "$node_id"
                    ;;
                "list"|"")
                    show_favorites
                    ;;
                *)
                    log_error "Usage: tfgrid-compose nodes favorite <add|remove|list> [node-id]"
                    exit 1
                    ;;
            esac
            ;;
        "help"|"-h"|"--help")
            echo ""
            echo "🔍 ThreeFold Node Browser"
            echo ""
            echo "Interactive browser with improved navigation:"
            echo "  • ↑/↓ arrows: Navigate between pages (20 nodes per page)"
            echo "  • PageUp/PageDown: Jump 5 pages at a time"
            echo "  • / key: Jump to specific node by typing ID"
            echo "  • f: Toggle favorite, d: Deploy, Enter: Details, q: Quit"
            echo ""
            echo "Usage:"
            echo "  tfgrid-compose nodes                    Interactive browser"
            echo "  tfgrid-compose nodes favorites          Show favorite nodes"
            echo "  tfgrid-compose nodes show <id>          Show node details"
            echo "  tfgrid-compose nodes favorite add <id>  Add to favorites"
            echo "  tfgrid-compose nodes favorite remove <id> Remove from favorites"
            echo ""
            ;;
        "")
            # Check if we have a TTY for interactive mode
            if [ -t 0 ]; then
                # Running interactively, start browser
                interactive_browser "$@"
                return $?
            else
                # Non-interactive mode - show error
                log_error "Interactive node browser requires a terminal (TTY)"
                log_info "Run 'tfgrid-compose nodes favorites' to list favorite nodes"
                log_info "Run 'tfgrid-compose nodes show <id>' to view node details"
                log_info "Run 'tfgrid-compose nodes favorite add <id>' to add favorites"
                return 1
            fi
            ;;
        *)
            log_error "Unknown subcommand: $subcommand"
            log_info "Run 'tfgrid-compose nodes help' for usage"
            exit 1
            ;;
    esac
}

# Export functions
export -f ensure_favorites_file
export -f add_favorite
export -f remove_favorite
export -f is_favorite
export -f get_favorites
export -f show_table_header
export -f show_node_row
export -f show_node_details
export -f interactive_browser
export -f show_favorites
export -f nodes_command