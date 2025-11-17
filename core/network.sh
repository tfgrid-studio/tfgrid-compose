#!/usr/bin/env bash
# TFGrid Compose - Network Management Module

# Network preference constants
readonly NETWORK_WIREGUARD="wireguard"
readonly NETWORK_MYCELIUM="mycelium"
readonly DEFAULT_NETWORK="$NETWORK_WIREGUARD"
readonly GLOBAL_NETWORK_FILE="$HOME/.config/tfgrid-compose/network-preference"

# Get network preference (deployment-specific or global fallback)
get_network_preference() {
    local app_name="$1"

    # If app name provided, check deployment-specific preference first
    if [ -n "$app_name" ]; then
        local state_dir=$(get_app_state_dir "$app_name")
        local state_file="$state_dir/state.yaml"

        if [ -f "$state_file" ]; then
            # Use yq if available, fallback to grep
            if command_exists yq; then
                local pref=$(yq eval '.preferred_network // empty' "$state_file")
                if [ -n "$pref" ] && [ "$pref" != "empty" ]; then
                    echo "$pref"
                    return 0
                fi
            else
                local pref=$(grep "^preferred_network:" "$state_file" | awk '{print $2}')
                if [ -n "$pref" ]; then
                    echo "$pref"
                    return 0
                fi
            fi
        fi
    fi

    # Fall back to global network preference
    get_global_network_preference
}

# Get global network preference
get_global_network_preference() {
    if [ -f "$GLOBAL_NETWORK_FILE" ]; then
        cat "$GLOBAL_NETWORK_FILE" 2>/dev/null || echo "$DEFAULT_NETWORK"
    else
        echo "$DEFAULT_NETWORK"
    fi
}

# Set global network preference
set_global_network_preference() {
    local network="$1"

    # Validate network type
    case "$network" in
        "$NETWORK_WIREGUARD"|"$NETWORK_MYCELIUM")
            ;;
        *)
            log_error "Invalid network: $network. Must be '$NETWORK_WIREGUARD' or '$NETWORK_MYCELIUM'"
            return 1
            ;;
    esac

    # Ensure directory exists
    mkdir -p "$(dirname "$GLOBAL_NETWORK_FILE")"

    # Set global preference
    echo "$network" > "$GLOBAL_NETWORK_FILE"
    log_success "Global network preference set to: $network"
    return 0
}

# Set network preference in deployment state
set_network_preference() {
    local app_name="$1"
    local network="$2"
    local state_dir=$(get_app_state_dir "$app_name")
    local state_file="$state_dir/state.yaml"

    # Validate network type
    case "$network" in
        "$NETWORK_WIREGUARD"|"$NETWORK_MYCELIUM")
            ;;
        *)
            log_error "Invalid network: $network. Must be '$NETWORK_WIREGUARD' or '$NETWORK_MYCELIUM'"
            return 1
            ;;
    esac

    # Ensure state file exists
    mkdir -p "$state_dir"

    # Update or add network preference
    if command_exists yq; then
        yq eval ".preferred_network = \"$network\"" -i "$state_file"
    else
        # Fallback using sed
        if grep -q "^preferred_network:" "$state_file"; then
            sed -i "s/^preferred_network:.*/preferred_network: $network/" "$state_file"
        else
            echo "preferred_network: $network" >> "$state_file"
        fi
    fi

    log_success "Network preference set to: $network"
    return 0
}

# Get appropriate IP address based on network preference
get_deployment_ip() {
    local app_name="$1"
    local state_dir=$(get_app_state_dir "$app_name")
    local state_file="$state_dir/state.yaml"
    local preferred_network=$(get_network_preference "$app_name")

    if [ "$preferred_network" = "$NETWORK_MYCELIUM" ]; then
        # Try mycelium IP first
        if command_exists yq; then
            local myc_ip=$(yq eval '.mycelium_ip // empty' "$state_file")
            if [ -n "$myc_ip" ] && [ "$myc_ip" != "null" ] && [ "$myc_ip" != "empty" ]; then
                echo "$myc_ip"
                return 0
            fi
        else
            local myc_ip=$(grep "^mycelium_ip:" "$state_file" | awk '{print $2}' || echo "")
            if [ -n "$myc_ip" ]; then
                echo "$myc_ip"
                return 0
            fi
        fi

        log_warning "Mycelium IP not available, falling back to wireguard"
    fi

    # Default to wireguard IP
    if command_exists yq; then
        yq eval '.vm_ip // empty' "$state_file"
    else
        grep "^vm_ip:" "$state_file" | awk '{print $2}' || echo ""
    fi
}

# Test connectivity to both networks
test_network_connectivity() {
    local app_name="$1"
    local state_dir=$(get_app_state_dir "$app_name")
    local state_file="$state_dir/state.yaml"

    echo "Testing network connectivity for $app_name..."
    echo ""

    # Get both IPs
    local wg_ip=""
    local myc_ip=""

    if command_exists yq; then
        wg_ip=$(yq eval '.vm_ip // empty' "$state_file")
        myc_ip=$(yq eval '.mycelium_ip // empty' "$state_file")
    else
        wg_ip=$(grep "^vm_ip:" "$state_file" | awk '{print $2}' || echo "")
        myc_ip=$(grep "^mycelium_ip:" "$state_file" | awk '{print $2}' || echo "")
    fi

    # Test wireguard (TCP connection to SSH port)
    if [ -n "$wg_ip" ]; then
        echo -n "WireGuard ($wg_ip): "
        if timeout 5 bash -c "echo > /dev/tcp/$wg_ip/22" 2>/dev/null; then
            echo "✅ reachable"
        else
            echo "❌ unreachable"
        fi
    fi

    # Test mycelium (ping6)
    if [ -n "$myc_ip" ]; then
        echo -n "Mycelium ($myc_ip): "
        if ping6 -c 1 -W 2 "$myc_ip" >/dev/null 2>&1; then
            echo "✅ reachable"
        else
            echo "❌ unreachable"
        fi
    fi
}

# Network subcommand handler
network_subcommand() {
    local subcommand="${1:-list}"
    shift

    case "$subcommand" in
        set)
            local app_name=$(get_smart_context)
            local network="$1"

            if [ -z "$network" ]; then
                echo ""
                echo "Usage: tfgrid-compose network set <wireguard|mycelium>"
                echo ""
                echo "This sets the global network preference for all deployments."
                echo "You can also set per-deployment preferences using:"
                echo "  tfgrid-compose select <app> && tfgrid-compose network set <network>"
                echo ""
                return 1
            fi

            # If we have a deployment context, set per-deployment preference
            if [ -n "$app_name" ]; then
                set_network_preference "$app_name" "$network"
            else
                # No deployment context - set global preference
                set_global_network_preference "$network"
            fi
            ;;

        get|show|current)
            local app_name=$(get_smart_context)

            if [ -n "$app_name" ]; then
                # Deployment-specific network preference
                local current=$(get_network_preference "$app_name")
                echo ""
                echo "Deployment: $app_name"
                echo "Current network: $current"
                echo ""

                # Show current IP being used
                local current_ip=$(get_deployment_ip "$app_name")
                case "$current" in
                    "$NETWORK_WIREGUARD")
                        echo "Active IP: $current_ip (WireGuard)"
                        ;;
                    "$NETWORK_MYCELIUM")
                        echo "Active IP: $current_ip (Mycelium)"
                        ;;
                esac
            else
                # No deployment context - show global preference
                local current=$(get_global_network_preference)
                echo ""
                echo "Global Network Preference"
                echo "========================"
                echo "Current network: $current"
                echo ""
                echo "This applies to all deployments that don't have specific preferences set."
                echo ""
                log_info "To set deployment-specific preferences:"
                echo "  tfgrid-compose select <app> && tfgrid-compose network set <network>"
            fi
            ;;

        list|available)
            echo ""
            echo "Available networks:"
            echo "  $NETWORK_WIREGUARD - Traditional VPN with private IPv4"
            echo "  $NETWORK_MYCELIUM  - Global IPv6 addressing"
            echo ""
            echo "Both networks are automatically provisioned during deployment."
            ;;

        test|verify)
            local app_name=$(get_smart_context)

            if [ -z "$app_name" ]; then
                log_error "No deployment selected."
                return 1
            fi

            test_network_connectivity "$app_name"
            ;;

        *)
            echo ""
            log_error "Unknown network subcommand: $subcommand"
            echo ""
            echo "Available subcommands:"
            echo "  set <network>     Set preferred network (wireguard|mycelium)"
            echo "  get, show         Show current network preference"
            echo "  list, available   List available networks"
            echo "  test, verify      Test connectivity to both networks"
            echo ""
            return 1
            ;;
    esac
}
