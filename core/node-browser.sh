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

    local current_index=0
    local view_mode="list"  # list or details

    while true; do
        case "$view_mode" in
            "list")
                # Show table view
                show_table_header

                # Show current page (10 nodes)
                local start_idx=$((current_index / 10 * 10))
                local end_idx=$((start_idx + 10))
                [ $end_idx -gt $node_count ] && end_idx=$node_count

                for ((i=start_idx; i<end_idx; i++)); do
                    local marker=""
                    if [ $i -eq $current_index ]; then
                        marker="→"
                    fi
                    echo -n "$marker"
                    show_node_row "${node_array[$i]}"
                done

                echo ""
                echo "Page $((start_idx/10 + 1)) of $(((node_count + 9) / 10))"
                echo "Node $((current_index + 1)) of $node_count selected"
                echo ""
                echo "Navigation: ↑/↓ arrows, PageUp/PageDown"
                echo "Actions: Enter=details, f=favorite, d=deploy, q=quit"
                echo ""
                read -rsn1 key

                case "$key" in
                    $'\x1b')  # Escape sequence
                        read -rsn2 -t 0.1 key2
                        case "$key2" in
                            "[A")  # Up arrow
                                [ $current_index -gt 0 ] && ((current_index--))
                                ;;
                            "[B")  # Down arrow
                                [ $current_index -lt $((node_count - 1)) ] && ((current_index++))
                                ;;
                            "[5")  # Page Up
                                current_index=$((current_index - 10))
                                [ $current_index -lt 0 ] && current_index=0
                                ;;
                            "[6")  # Page Down
                                current_index=$((current_index + 10))
                                [ $current_index -ge $node_count ] && current_index=$((node_count - 1))
                                ;;
                        esac
                        ;;
                    "")  # Enter
                        view_mode="details"
                        ;;
                    "f"|"F")
                        local node_id=$(echo "${node_array[$current_index]}" | jq -r '.nodeId')
                        if is_favorite "$node_id"; then
                            remove_favorite "$node_id"
                        else
                            add_favorite "$node_id"
                        fi
                        ;;
                    "d"|"D")
                        local node_id=$(echo "${node_array[$current_index]}" | jq -r '.nodeId')
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
                # Show detailed view
                show_node_details "${node_array[$current_index]}"

                read -rsn1 key
                case "$key" in
                    "f"|"F")
                        local node_id=$(echo "${node_array[$current_index]}" | jq -r '.nodeId')
                        if is_favorite "$node_id"; then
                            remove_favorite "$node_id"
                        else
                            add_favorite "$node_id"
                        fi
                        ;;
                    "d"|"D")
                        local node_id=$(echo "${node_array[$current_index]}" | jq -r '.nodeId')
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
    printf "%-6s %-20s %-15s %-6s %-6s %-6s %-6s %-8s %-10s\n" "ID" "Farm" "Location" "CPU" "RAM" "Disk" "IPv4" "Load" "Uptime"
    echo "────────────────────────────────────────────────────────────────────────────────"

    local count=0
    while IFS= read -r node_id; do
        [ -z "$node_id" ] && continue

        # Try to get node info
        local node_info=$(curl -s "${GRIDPROXY_URL}/nodes?node_id=${node_id}")
        if [ $? -eq 0 ] && [ -n "$node_info" ]; then
            local node=$(echo "$node_info" | jq -r '.[0]')
            if [ "$node" != "null" ] && [ -n "$node" ]; then
                show_node_row "$node"
                ((count++))
            fi
        fi
    done <<< "$favorites"

    if [ $count -eq 0 ]; then
        echo ""
        log_info "No favorite nodes are currently online"
    else
        echo ""
        echo "Legend: ID=Node ID, Farm=Farm Name, Location=City/Country, CPU=Total Cores"
        echo "        RAM=Total GB, Disk=Total TB, IPv4=IPv4 Available, Load=CPU Usage %, Uptime=Days"
    fi
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