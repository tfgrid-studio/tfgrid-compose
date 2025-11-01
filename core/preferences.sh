#!/usr/bin/env bash
# Preferences management for TFGrid Compose - Whitelist/Blacklist System

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Preferences file location
PREFERENCES_FILE="$HOME/.config/tfgrid-compose/preferences.yaml"
CONFIG_DIR="$HOME/.config/tfgrid-compose"

# Ensure preferences directory exists
ensure_preferences_dir() {
    mkdir -p "$CONFIG_DIR"
}

# Initialize preferences file with default structure
init_preferences() {
    ensure_preferences_dir
    
    if [ -f "$PREFERENCES_FILE" ]; then
        return 0
    fi
    
    local current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat > "$PREFERENCES_FILE" << EOF
# TFGrid Compose Preferences
# Persistent whitelist/blacklist settings for all deployments
# Generated on $current_time

whitelist:
  nodes: []
  farms: []

blacklist:
  nodes: []
  farms: []

preferences:
  max_cpu_usage: 80
  max_disk_usage: 60
  min_uptime_days: 3

metadata:
  version: "1.0"
  created: "$current_time"
  last_updated: "$current_time"
EOF
    
    log_success "Created preferences file: $PREFERENCES_FILE"
}

# Update the last_updated timestamp
update_timestamp() {
    local current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if [ -f "$PREFERENCES_FILE" ]; then
        sed -i "s/last_updated: \"[^\"]*\"/last_updated: \"$current_time\"/" "$PREFERENCES_FILE"
    fi
}

# Get preference value using simple YAML parsing
yaml_get_value() {
    local file="$1"
    local section="$2"
    local key="$3"
    
    if [ ! -f "$file" ]; then
        echo ""
        return
    fi
    
    # Use a simpler approach with basic string manipulation
    case "$section" in
        "whitelist.nodes")
            # Extract everything between [ and ] for nodes in whitelist
            local line=$(grep -A 2 "^whitelist:" "$file" | grep "nodes:")
            if [ -n "$line" ]; then
                # Remove "  nodes: [" from start and "]" from end, replace commas with spaces
                echo "$line" | sed 's/^  nodes: *\[//' | sed 's/\].*$//' | sed 's/,/ /g' | sed 's/^ *//' | sed 's/ *$//'
            fi
            ;;
        "whitelist.farms")
            # Extract everything between [ and ] for farms in whitelist
            local line=$(grep -A 2 "^whitelist:" "$file" | grep "farms:")
            if [ -n "$line" ]; then
                # Remove "  farms: [" from start and "]" from end, replace commas with spaces
                echo "$line" | sed 's/^  farms: *\[//' | sed 's/\].*$//' | sed 's/,/ /g' | sed 's/^ *//' | sed 's/ *$//'
            fi
            ;;
        "blacklist.nodes")
            # Extract everything between [ and ] for nodes in blacklist
            local line=$(grep -A 2 "^blacklist:" "$file" | grep "nodes:")
            if [ -n "$line" ]; then
                # Remove "  nodes: [" from start and "]" from end, replace commas with spaces
                echo "$line" | sed 's/^  nodes: *\[//' | sed 's/\].*$//' | sed 's/,/ /g' | sed 's/^ *//' | sed 's/ *$//'
            fi
            ;;
        "blacklist.farms")
            # Extract everything between [ and ] for farms in blacklist
            local line=$(grep -A 2 "^blacklist:" "$file" | grep "farms:")
            if [ -n "$line" ]; then
                # Remove "  farms: [" from start and "]" from end, replace commas with spaces
                echo "$line" | sed 's/^  farms: *\[//' | sed 's/\].*$//' | sed 's/,/ /g' | sed 's/^ *//' | sed 's/ *$//'
            fi
            ;;
        "preferences.max_cpu_usage")
            local line=$(grep -A 3 "^preferences:" "$file" | grep "max_cpu_usage:")
            echo "$line" | sed 's/^  max_cpu_usage: *//' | sed 's/^ *//' | sed 's/ *$//'
            ;;
        "preferences.max_disk_usage")
            local line=$(grep -A 3 "^preferences:" "$file" | grep "max_disk_usage:")
            echo "$line" | sed 's/^  max_disk_usage: *//' | sed 's/^ *//' | sed 's/ *$//'
            ;;
        "preferences.min_uptime_days")
            local line=$(grep -A 3 "^preferences:" "$file" | grep "min_uptime_days:")
            echo "$line" | sed 's/^  min_uptime_days: *//' | sed 's/^ *//' | sed 's/ *$//'
            ;;
        "metadata.created")
            local line=$(grep "created:" "$file")
            echo "$line" | sed 's/^  created: *//' | sed 's/^ *//' | sed 's/ *$//'
            ;;
        "metadata.last_updated")
            local line=$(grep "last_updated:" "$file")
            echo "$line" | sed 's/^  last_updated: *//' | sed 's/^ *//' | sed 's/ *$//'
            ;;
        *)
            echo ""
            ;;
    esac
}

# Update preference using yaml modification
yaml_update_value() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"
    
    if [ ! -f "$file" ]; then
        init_preferences
    fi
    
    case "$section" in
        "whitelist.nodes")
            sed -i "/^whitelist:/,/^  farms:/ s/^  nodes: \[.*\]/  nodes: [$value]/" "$file"
            ;;
        "whitelist.farms")
            sed -i "/^whitelist:/,/^blacklist:/ s/^  farms: \[.*\]/  farms: [$value]/" "$file"
            ;;
        "blacklist.nodes")
            sed -i "/^blacklist:/,/^  farms:/ s/^  nodes: \[.*\]/  nodes: [$value]/" "$file"
            ;;
        "blacklist.farms")
            sed -i "/^blacklist:/,/^preferences:/ s/^  farms: \[.*\]/  farms: [$value]/" "$file"
            ;;
        "preferences.max_cpu_usage")
            sed -i "/^preferences:/,/^  max_disk_usage:/ s/^  max_cpu_usage: .*/  max_cpu_usage: $value/" "$file"
            ;;
        "preferences.max_disk_usage")
            sed -i "/^preferences:/,/^  min_uptime_days:/ s/^  max_disk_usage: .*/  max_disk_usage: $value/" "$file"
            ;;
        "preferences.min_uptime_days")
            sed -i "/^preferences:/,/^metadata:/ s/^  min_uptime_days: .*/  min_uptime_days: $value/" "$file"
            ;;
    esac
    
    update_timestamp
}

# Get whitelist nodes as comma-separated list
get_whitelist_nodes() {
    init_preferences
    local nodes=$(yaml_get_value "$PREFERENCES_FILE" "whitelist.nodes")
    echo "${nodes// /,}"  # Replace spaces with commas
}

# Get whitelist farms as comma-separated list
get_whitelist_farms() {
    init_preferences
    local farms=$(yaml_get_value "$PREFERENCES_FILE" "whitelist.farms")
    echo "${farms// /,}"  # Replace spaces with commas
}

# Get blacklist nodes as comma-separated list
get_blacklist_nodes() {
    init_preferences
    local nodes=$(yaml_get_value "$PREFERENCES_FILE" "blacklist.nodes")
    echo "${nodes// /,}"  # Replace spaces with commas
}

# Get blacklist farms as comma-separated list
get_blacklist_farms() {
    init_preferences
    local farms=$(yaml_get_value "$PREFERENCES_FILE" "blacklist.farms")
    echo "${farms// /,}"  # Replace spaces with commas
}

# Get preference value
get_preference() {
    local pref_name="$1"
    
    case "$pref_name" in
        "max_cpu_usage")
            echo "$(yaml_get_value "$PREFERENCES_FILE" "preferences.max_cpu_usage")"
            ;;
        "max_disk_usage")
            echo "$(yaml_get_value "$PREFERENCES_FILE" "preferences.max_disk_usage")"
            ;;
        "min_uptime_days")
            echo "$(yaml_get_value "$PREFERENCES_FILE" "preferences.min_uptime_days")"
            ;;
        "created")
            echo "$(yaml_get_value "$PREFERENCES_FILE" "metadata.created")"
            ;;
        "last_updated")
            echo "$(yaml_get_value "$PREFERENCES_FILE" "metadata.last_updated")"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Update whitelist nodes
update_whitelist_nodes() {
    local nodes="$1"
    
    if [ -z "$nodes" ]; then
        log_error "No node IDs provided"
        return 1
    fi
    
    # Validate node IDs (should be numeric)
    local valid=true
    IFS=',' read -ra NODE_ARRAY <<< "$nodes"
    for node in "${NODE_ARRAY[@]}"; do
        if ! [[ "$node" =~ ^[0-9]+$ ]]; then
            log_error "Invalid node ID: $node (must be numeric)"
            valid=false
        fi
    done
    
    if [ "$valid" = false ]; then
        return 1
    fi
    
    init_preferences
    yaml_update_value "$PREFERENCES_FILE" "whitelist.nodes" "" "$nodes"
    log_success "Updated whitelist nodes: $nodes"
}

# Update whitelist farms (case-insensitive, names only)
update_whitelist_farms() {
    local farms_input="$1"
    
    if [ -z "$farms_input" ]; then
        log_error "No farm names provided"
        return 1
    fi
    
    init_preferences
    
    # Just use the input as-is for farm names (they should already be comma-separated)
    local normalized_farms=$(echo "$farms_input" | tr -s ' ' | sed 's/ *, */,/g' | sed 's/^,//' | sed 's/,$//')
    
    yaml_update_value "$PREFERENCES_FILE" "whitelist.farms" "" "$normalized_farms"
    log_success "Updated whitelist farms: $farms_input"
}

# Update blacklist nodes
update_blacklist_nodes() {
    local nodes="$1"
    
    if [ -z "$nodes" ]; then
        log_error "No node IDs provided"
        return 1
    fi
    
    # Validate node IDs (should be numeric)
    local valid=true
    IFS=',' read -ra NODE_ARRAY <<< "$nodes"
    for node in "${NODE_ARRAY[@]}"; do
        if ! [[ "$node" =~ ^[0-9]+$ ]]; then
            log_error "Invalid node ID: $node (must be numeric)"
            valid=false
        fi
    done
    
    if [ "$valid" = false ]; then
        return 1
    fi
    
    init_preferences
    yaml_update_value "$PREFERENCES_FILE" "blacklist.nodes" "" "$nodes"
    log_success "Updated blacklist nodes: $nodes"
}

# Update blacklist farms (case-insensitive, names only)
update_blacklist_farms() {
    local farms_input="$1"
    
    if [ -z "$farms_input" ]; then
        log_error "No farm names provided"
        return 1
    fi
    
    init_preferences
    
    # Just use the input as-is for farm names (they should already be comma-separated)
    local normalized_farms=$(echo "$farms_input" | tr -s ' ' | sed 's/ *, */,/g' | sed 's/^,//' | sed 's/,$//')
    
    yaml_update_value "$PREFERENCES_FILE" "blacklist.farms" "" "$normalized_farms"
    log_success "Updated blacklist farms: $farms_input"
}

# Update general preference
update_preference() {
    local pref_name="$1"
    local value="$2"
    
    if [ -z "$pref_name" ] || [ -z "$value" ]; then
        log_error "Preference name and value required"
        return 1
    fi
    
    # Validate preference values
    case "$pref_name" in
        "max_cpu_usage"|"max_disk_usage")
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 0 ] || [ "$value" -gt 100 ]; then
                log_error "$pref_name must be a number between 0 and 100"
                return 1
            fi
            ;;
        "min_uptime_days")
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 0 ]; then
                log_error "$pref_name must be a positive number"
                return 1
            fi
            ;;
    esac
    
    init_preferences
    yaml_update_value "$PREFERENCES_FILE" "preferences.$pref_name" "" "$value"
    log_success "Updated preference $pref_name: $value"
}

# Clear whitelist
clear_whitelist() {
    init_preferences
    yaml_update_value "$PREFERENCES_FILE" "whitelist.nodes" "" ""
    yaml_update_value "$PREFERENCES_FILE" "whitelist.farms" "" ""
    log_success "Cleared whitelist"
}

# Clear blacklist
clear_blacklist() {
    init_preferences
    yaml_update_value "$PREFERENCES_FILE" "blacklist.nodes" "" ""
    yaml_update_value "$PREFERENCES_FILE" "blacklist.farms" "" ""
    log_success "Cleared blacklist"
}

# Clear all preferences
clear_all_preferences() {
    init_preferences
    yaml_update_value "$PREFERENCES_FILE" "whitelist.nodes" "" ""
    yaml_update_value "$PREFERENCES_FILE" "whitelist.farms" "" ""
    yaml_update_value "$PREFERENCES_FILE" "blacklist.nodes" "" ""
    yaml_update_value "$PREFERENCES_FILE" "blacklist.farms" "" ""
    yaml_update_value "$PREFERENCES_FILE" "preferences.max_cpu_usage" "" "80"
    yaml_update_value "$PREFERENCES_FILE" "preferences.max_disk_usage" "" "60"
    yaml_update_value "$PREFERENCES_FILE" "preferences.min_uptime_days" "" "3"
    log_success "Cleared all preferences (restored defaults)"
}

# Show all preferences
show_preferences() {
    if [ ! -f "$PREFERENCES_FILE" ]; then
        log_info "No preferences file found"
        return
    fi
    
    echo ""
    echo "🎯 TFGrid Compose Preferences"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "File: $PREFERENCES_FILE"
    echo ""
    
    echo "📋 Whitelist:"
    local wl_nodes=$(get_whitelist_nodes)
    local wl_farms=$(get_whitelist_farms)
    echo "  Nodes: ${wl_nodes:-none}"
    echo "  Farms: ${wl_farms:-none}"
    
    echo ""
    echo "🚫 Blacklist:"
    local bl_nodes=$(get_blacklist_nodes)
    local bl_farms=$(get_blacklist_farms)
    echo "  Nodes: ${bl_nodes:-none}"
    echo "  Farms: ${bl_farms:-none}"
    
    echo ""
    echo "⚙️  General Preferences:"
    local max_cpu=$(get_preference "max_cpu_usage")
    local max_disk=$(get_preference "max_disk_usage")
    local min_uptime=$(get_preference "min_uptime_days")
    echo "  Max CPU Usage: ${max_cpu:-80}%"
    echo "  Max Disk Usage: ${max_disk:-60}%"
    echo "  Min Uptime: ${min_uptime:-3} days"
    
    echo ""
    echo "📅 Metadata:"
    local created=$(get_preference "created")
    local last_updated=$(get_preference "last_updated")
    echo "  Created: $created"
    echo "  Last Updated: $last_updated"
    
    echo ""
}

# Interactive setup for preferences
interactive_setup() {
    echo ""
    echo "🎯 TFGrid Compose Preferences - Interactive Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    local wl_nodes=$(get_whitelist_nodes)
    local wl_farms=$(get_whitelist_farms)
    local bl_nodes=$(get_blacklist_nodes)
    local bl_farms=$(get_blacklist_farms)
    
    echo "📋 WHITELIST (Preferred nodes/farms):"
    echo ""
    echo "Current whitelist nodes: ${wl_nodes:-none}"
    read -p "Enter node IDs to whitelist (comma-separated): " new_wl_nodes
    
    echo ""
    echo "Current whitelist farms: ${wl_farms:-none}"
    read -p "Enter farm names to whitelist (comma-separated): " new_wl_farms
    new_wl_farms=${new_wl_farms:-$wl_farms}
    
    echo ""
    echo "🚫 BLACKLIST (Nodes/farms to avoid):"
    echo ""
    echo "Current blacklist nodes: ${bl_nodes:-none}"
    read -p "Enter node IDs to blacklist (comma-separated): " new_bl_nodes
    
    echo ""
    echo "Current blacklist farms: ${bl_farms:-none}"
    read -p "Enter farm names to blacklist (comma-separated, or press Enter to keep current): " new_bl_farms
    new_bl_farms=${new_bl_farms:-$bl_farms}
    
    echo ""
    echo "⚙️  GENERAL PREFERENCES:"
    echo ""
    local current_cpu=$(get_preference "max_cpu_usage")
    local current_disk=$(get_preference "max_disk_usage")
    local current_uptime=$(get_preference "min_uptime_days")
    
    read -p "Max CPU usage % [$current_cpu]: " new_cpu
    new_cpu=${new_cpu:-$current_cpu}
    
    read -p "Max disk usage % [$current_disk]: " new_disk
    new_disk=${new_disk:-$current_disk}
    
    read -p "Min uptime days [$current_uptime]: " new_uptime
    new_uptime=${new_uptime:-$current_uptime}
    
    # Apply changes
    [ -n "$new_wl_nodes" ] && update_whitelist_nodes "$new_wl_nodes"
    [ -n "$new_wl_farms" ] && update_whitelist_farms "$new_wl_farms"
    [ -n "$new_bl_nodes" ] && update_blacklist_nodes "$new_bl_nodes"
    [ -n "$new_bl_farms" ] && update_blacklist_farms "$new_bl_farms"
    [ -n "$new_cpu" ] && update_preference "max_cpu_usage" "$new_cpu"
    [ -n "$new_disk" ] && update_preference "max_disk_usage" "$new_disk"
    [ -n "$new_uptime" ] && update_preference "min_uptime_days" "$new_uptime"
    
    echo ""
    show_preferences
}

# Export preferences as environment variables for deployment
export_for_deployment() {
    init_preferences
    
    # Export whitelist/blacklist as environment variables
    local wl_nodes=$(get_whitelist_nodes)
    local wl_farms=$(get_whitelist_farms)
    local bl_nodes=$(get_blacklist_nodes)
    local bl_farms=$(get_blacklist_farms)
    local max_cpu=$(get_preference "max_cpu_usage")
    local max_disk=$(get_preference "max_disk_usage")
    local min_uptime=$(get_preference "min_uptime_days")
    
    # Export as CUSTOM_* variables for the deployment system
    export CUSTOM_WHITELIST_NODES="$wl_nodes"
    export CUSTOM_WHITELIST_FARMS="$wl_farms"
    export CUSTOM_BLACKLIST_NODES="$bl_nodes"
    export CUSTOM_BLACKLIST_FARMS="$bl_farms"
    export CUSTOM_MAX_CPU_USAGE="$max_cpu"
    export CUSTOM_MAX_DISK_USAGE="$max_disk"
    export CUSTOM_MIN_UPTIME_DAYS="$min_uptime"
}

# Whitelist command handler
cmd_whitelist() {
    local subcommand="$1"
    shift || true
    
    case "$subcommand" in
        "nodes"|"n")
            # Whitelist nodes
            if [ -z "$1" ]; then
                if [ "$1" = "--status" ]; then
                    show_whitelist_status "nodes"
                elif [ "$1" = "--clear" ]; then
                    init_preferences
                    yaml_update_value "$PREFERENCES_FILE" "whitelist.nodes" ""
                    log_success "Cleared whitelist nodes"
                else
                    log_error "Usage: tfgrid-compose whitelist nodes <node_ids> | --status | --clear"
                    exit 1
                fi
            else
                update_whitelist_nodes "$1"
            fi
            ;;
        "farms"|"f")
            # Whitelist farms
            if [ -z "$1" ]; then
                if [ "$1" = "--status" ]; then
                    show_whitelist_status "farms"
                elif [ "$1" = "--clear" ]; then
                    init_preferences
                    yaml_update_value "$PREFERENCES_FILE" "whitelist.farms" ""
                    log_success "Cleared whitelist farms"
                else
                    log_error "Usage: tfgrid-compose whitelist farms <farm_names> | --status | --clear"
                    exit 1
                fi
            else
                update_whitelist_farms "$1"
            fi
            ;;
        "--status"|"status"|"-s")
            # Show whitelist status
            show_whitelist_status "all"
            ;;
        "--clear"|"clear"|"-c")
            # Clear whitelist
            clear_whitelist
            ;;
        *)
            # No subcommand - interactive setup
            interactive_setup_whitelist
            ;;
    esac
}

# Blacklist command handler
cmd_blacklist() {
    local subcommand="$1"
    shift || true
    
    case "$subcommand" in
        "nodes"|"n")
            # Blacklist nodes
            if [ -z "$1" ]; then
                if [ "$1" = "--status" ]; then
                    show_blacklist_status "nodes"
                elif [ "$1" = "--clear" ]; then
                    init_preferences
                    yaml_update_value "$PREFERENCES_FILE" "blacklist.nodes" ""
                    log_success "Cleared blacklist nodes"
                else
                    log_error "Usage: tfgrid-compose blacklist nodes <node_ids> | --status | --clear"
                    exit 1
                fi
            else
                update_blacklist_nodes "$1"
            fi
            ;;
        "farms"|"f")
            # Blacklist farms
            if [ -z "$1" ]; then
                if [ "$1" = "--status" ]; then
                    show_blacklist_status "farms"
                elif [ "$1" = "--clear" ]; then
                    init_preferences
                    yaml_update_value "$PREFERENCES_FILE" "blacklist.farms" ""
                    log_success "Cleared blacklist farms"
                else
                    log_error "Usage: tfgrid-compose blacklist farms <farm_names> | --status | --clear"
                    exit 1
                fi
            else
                update_blacklist_farms "$1"
            fi
            ;;
        "--status"|"status"|"-s")
            # Show blacklist status
            show_blacklist_status "all"
            ;;
        "--clear"|"clear"|"-c")
            # Clear blacklist
            clear_blacklist
            ;;
        *)
            # No subcommand - interactive setup
            interactive_setup_blacklist
            ;;
    esac
}

# Preferences command handler
cmd_preferences() {
    local option="$1"
    
    case "$option" in
        "--status"|"status"|"-s"|"")
            # Show all preferences
            show_preferences
            ;;
        "--clear"|"clear"|"-c")
            # Clear all preferences
            echo ""
            echo "⚠️  This will clear ALL preferences and restore defaults!"
            read -p "Are you sure? (yes/no): " confirm
            if [ "$confirm" = "yes" ]; then
                clear_all_preferences
            else
                log_info "Cancelled - preferences unchanged"
            fi
            ;;
        *)
            log_error "Unknown option: $option"
            log_info "Usage: tfgrid-compose preferences [--status | --clear]"
            exit 1
            ;;
    esac
}

# Helper functions for specific status displays
show_whitelist_status() {
    local type="$1"
    
    case "$type" in
        "nodes")
            local nodes=$(get_whitelist_nodes)
            echo ""
            echo "📋 Whitelist Nodes: ${nodes:-none}"
            ;;
        "farms")
            local farms=$(get_whitelist_farms)
            echo ""
            echo "📋 Whitelist Farms: ${farms:-none}"
            ;;
        "all")
            echo ""
            echo "📋 Current Whitelist:"
            local nodes=$(get_whitelist_nodes)
            local farms=$(get_whitelist_farms)
            echo "  Nodes: ${nodes:-none}"
            echo "  Farms: ${farms:-none}"
            ;;
    esac
    echo ""
}

show_blacklist_status() {
    local type="$1"
    
    case "$type" in
        "nodes")
            local nodes=$(get_blacklist_nodes)
            echo ""
            echo "🚫 Blacklist Nodes: ${nodes:-none}"
            ;;
        "farms")
            local farms=$(get_blacklist_farms)
            echo ""
            echo "🚫 Blacklist Farms: ${farms:-none}"
            ;;
        "all")
            echo ""
            echo "🚫 Current Blacklist:"
            local nodes=$(get_blacklist_nodes)
            local farms=$(get_blacklist_farms)
            echo "  Nodes: ${nodes:-none}"
            echo "  Farms: ${farms:-none}"
            ;;
    esac
    echo ""
}

# Clear specific list functions
clear_whitelist_nodes() {
    init_preferences
    yaml_update_value "$PREFERENCES_FILE" "whitelist.nodes" "" ""
    log_success "Cleared whitelist nodes"
}

clear_whitelist_farms() {
    init_preferences
    yaml_update_value "$PREFERENCES_FILE" "whitelist.farms" "" ""
    log_success "Cleared whitelist farms"
}

clear_blacklist_nodes() {
    init_preferences
    yaml_update_value "$PREFERENCES_FILE" "blacklist.nodes" "" ""
    log_success "Cleared blacklist nodes"
}

clear_blacklist_farms() {
    init_preferences
    yaml_update_value "$PREFERENCES_FILE" "blacklist.farms" "" ""
    log_success "Cleared blacklist farms"
}

# Interactive setup for just whitelist
interactive_setup_whitelist() {
    echo ""
    echo "📋 Whitelist Setup"
    echo "━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    local wl_nodes=$(get_whitelist_nodes)
    local wl_farms=$(get_whitelist_farms)
    
    echo "Current whitelist nodes: ${wl_nodes:-none}"
    read -p "Enter node IDs to whitelist (comma-separated): " new_wl_nodes
    
    echo ""
    echo "Current whitelist farms: ${wl_farms:-none}"
    read -p "Enter farm names to whitelist (comma-separated): " new_wl_farms
    new_wl_farms=${new_wl_farms:-$wl_farms}
    
    [ -n "$new_wl_nodes" ] && update_whitelist_nodes "$new_wl_nodes"
    [ -n "$new_wl_farms" ] && update_whitelist_farms "$new_wl_farms"
    
    echo ""
    show_whitelist_status "all"
}

# Interactive setup for just blacklist
interactive_setup_blacklist() {
    echo ""
    echo "🚫 Blacklist Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    local bl_nodes=$(get_blacklist_nodes)
    local bl_farms=$(get_blacklist_farms)
    
    echo "Current blacklist nodes: ${bl_nodes:-none}"
    read -p "Enter node IDs to blacklist (comma-separated): " new_bl_nodes
    
    echo ""
    echo "Current blacklist farms: ${bl_farms:-none}"
    read -p "Enter farm names to blacklist (comma-separated, or press Enter to keep current): " new_bl_farms
    new_bl_farms=${new_bl_farms:-$bl_farms}
    
    [ -n "$new_bl_nodes" ] && update_blacklist_nodes "$new_bl_nodes"
    [ -n "$new_bl_farms" ] && update_blacklist_farms "$new_bl_farms"
    
    echo ""
    show_blacklist_status "all"
}

# Export all functions
export -f init_preferences
export -f get_whitelist_nodes
export -f get_whitelist_farms
export -f get_blacklist_nodes
export -f get_blacklist_farms
export -f get_preference
export -f update_whitelist_nodes
export -f update_whitelist_farms
export -f update_blacklist_nodes
export -f update_blacklist_farms
export -f update_preference
export -f clear_whitelist
export -f clear_blacklist
export -f clear_all_preferences
export -f show_preferences
export -f interactive_setup
export -f export_for_deployment
export -f cmd_whitelist
export -f cmd_blacklist
export -f cmd_preferences
export -f show_whitelist_status
export -f show_blacklist_status
export -f clear_whitelist_nodes
export -f clear_whitelist_farms
export -f clear_blacklist_nodes
export -f clear_blacklist_farms
export -f interactive_setup_whitelist
export -f interactive_setup_blacklist