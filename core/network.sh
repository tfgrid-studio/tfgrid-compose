#!/usr/bin/env bash
# TFGrid Compose - Network Management Module

# Guard against multiple sourcing
[ -n "${_TFGRID_NETWORK_SH_SOURCED:-}" ] && return 0
readonly _TFGRID_NETWORK_SH_SOURCED=1

# Source required modules
source "$(dirname "${BASH_SOURCE[0]}")/deployment-state.sh"

# Network type constants (ordered by security: encrypted/overlay first)
if [ -z "${NETWORK_MYCELIUM:-}" ]; then
    readonly NETWORK_MYCELIUM="mycelium"
    readonly NETWORK_WIREGUARD="wireguard"
    readonly NETWORK_IPV4="ipv4"
    readonly NETWORK_IPV6="ipv6"
    readonly ALL_NETWORKS="mycelium,wireguard,ipv4,ipv6"

    # Default settings (prefer secure networks)
    readonly DEFAULT_PROVISION="mycelium,ipv4"
    readonly DEFAULT_PREFER="mycelium,ipv4"

    # Config files
    readonly GLOBAL_PROVISION_FILE="$HOME/.config/tfgrid-compose/network-provision"
    readonly GLOBAL_PREFER_FILE="$HOME/.config/tfgrid-compose/network-prefer"

    # Legacy files (for migration info)
    readonly LEGACY_NETWORK_FILE="$HOME/.config/tfgrid-compose/network-preference"
    readonly LEGACY_MODE_FILE="$HOME/.config/tfgrid-compose/network-mode"
fi

# Validate network list (comma-separated)
validate_networks() {
    local networks="$1"
    local valid_networks="ipv4 ipv6 mycelium wireguard all"

    IFS=',' read -ra NET_ARRAY <<< "$networks"
    for net in "${NET_ARRAY[@]}"; do
        net=$(echo "$net" | tr -d ' ')
        if [[ ! " $valid_networks " =~ " $net " ]]; then
            log_error "Invalid network: $net"
            log_info "Valid networks: ipv4, ipv6, mycelium, wireguard, all"
            return 1
        fi
    done
    return 0
}

# Expand 'all' to full network list
expand_networks() {
    local networks="$1"
    if [ "$networks" = "all" ]; then
        echo "$ALL_NETWORKS"
    else
        echo "$networks"
    fi
}

# Get global provision setting
get_global_provision() {
    if [ -f "$GLOBAL_PROVISION_FILE" ]; then
        cat "$GLOBAL_PROVISION_FILE" 2>/dev/null || echo "$DEFAULT_PROVISION"
    else
        echo "$DEFAULT_PROVISION"
    fi
}

# Set global provision setting
set_global_provision() {
    local networks="$1"

    if ! validate_networks "$networks"; then
        return 1
    fi

    networks=$(expand_networks "$networks")

    mkdir -p "$(dirname "$GLOBAL_PROVISION_FILE")"
    echo "$networks" > "$GLOBAL_PROVISION_FILE"
    log_success "Network provisioning set to: $networks"
    return 0
}

# Get global prefer setting (ordered list)
get_global_prefer() {
    if [ -f "$GLOBAL_PREFER_FILE" ]; then
        cat "$GLOBAL_PREFER_FILE" 2>/dev/null || echo "$DEFAULT_PREFER"
    else
        echo "$DEFAULT_PREFER"
    fi
}

# Set global prefer setting
set_global_prefer() {
    local networks="$1"

    if ! validate_networks "$networks"; then
        return 1
    fi

    # Don't expand 'all' for prefer - it doesn't make sense
    if [ "$networks" = "all" ]; then
        log_error "Cannot use 'all' for connection preference. Specify order explicitly."
        log_info "Example: t network prefer mycelium,ipv4,wireguard"
        return 1
    fi

    mkdir -p "$(dirname "$GLOBAL_PREFER_FILE")"
    echo "$networks" > "$GLOBAL_PREFER_FILE"
    log_success "Connection preference set to: $networks (in order)"
    return 0
}

# Get deployment-specific prefer setting
get_deployment_prefer() {
    local deployment_id="$1"
    local state_dir="$HOME/.config/tfgrid-compose/state/$deployment_id"
    local state_file="$state_dir/state.yaml"

    if [ -f "$state_file" ] && command_exists yq; then
        local pref=$(yq eval '.network_prefer' "$state_file" 2>/dev/null)
        if [ -n "$pref" ] && [ "$pref" != "null" ]; then
            echo "$pref"
            return 0
        fi
    fi

    # Fall back to global
    get_global_prefer
}

# Set deployment-specific prefer setting
set_deployment_prefer() {
    local deployment_id="$1"
    local networks="$2"
    local state_dir="$HOME/.config/tfgrid-compose/state/$deployment_id"
    local state_file="$state_dir/state.yaml"

    if ! validate_networks "$networks"; then
        return 1
    fi

    if [ "$networks" = "all" ]; then
        log_error "Cannot use 'all' for connection preference."
        return 1
    fi

    if [ ! -d "$state_dir" ]; then
        log_error "Deployment not found: $deployment_id"
        return 1
    fi

    if command_exists yq; then
        yq eval ".network_prefer = \"$networks\"" -i "$state_file"
        log_success "Deployment connection preference set to: $networks"
    else
        log_error "yq required for deployment-specific settings"
        return 1
    fi

    return 0
}

# Get the best IP address based on preference order
# Returns: ip_address|network_type
get_preferred_ip() {
    local deployment_id="$1"
    local override="$2"  # Optional: force specific network

    local registry_file="$HOME/.config/tfgrid-compose/deployments.yaml"

    if [ ! -f "$registry_file" ]; then
        return 1
    fi

    # Get available addresses
    local ipv4_addr=$(yq eval ".deployments.\"$deployment_id\".ipv4_address" "$registry_file" 2>/dev/null)
    local ipv6_addr=$(yq eval ".deployments.\"$deployment_id\".ipv6_address" "$registry_file" 2>/dev/null)
    local mycelium_addr=$(yq eval ".deployments.\"$deployment_id\".mycelium_address" "$registry_file" 2>/dev/null)
    local wireguard_addr=$(yq eval ".deployments.\"$deployment_id\".wireguard_address" "$registry_file" 2>/dev/null)

    # Clean null values
    [ "$ipv4_addr" = "null" ] && ipv4_addr=""
    [ "$ipv6_addr" = "null" ] && ipv6_addr=""
    [ "$mycelium_addr" = "null" ] && mycelium_addr=""
    [ "$wireguard_addr" = "null" ] && wireguard_addr=""

    # If override specified, use only that network
    if [ -n "$override" ]; then
        case "$override" in
            ipv4)
                if [ -n "$ipv4_addr" ]; then
                    echo "$ipv4_addr|ipv4"
                    return 0
                fi
                ;;
            ipv6)
                if [ -n "$ipv6_addr" ]; then
                    echo "$ipv6_addr|ipv6"
                    return 0
                fi
                ;;
            mycelium)
                if [ -n "$mycelium_addr" ]; then
                    echo "$mycelium_addr|mycelium"
                    return 0
                fi
                ;;
            wireguard)
                if [ -n "$wireguard_addr" ]; then
                    echo "$wireguard_addr|wireguard"
                    return 0
                fi
                ;;
        esac
        return 1
    fi

    # Get preference order
    local prefer_list=$(get_deployment_prefer "$deployment_id")

    # Try each network in preference order
    IFS=',' read -ra PREFER_ARRAY <<< "$prefer_list"
    for net in "${PREFER_ARRAY[@]}"; do
        net=$(echo "$net" | tr -d ' ')
        case "$net" in
            ipv4)
                if [ -n "$ipv4_addr" ]; then
                    echo "$ipv4_addr|ipv4"
                    return 0
                fi
                ;;
            ipv6)
                if [ -n "$ipv6_addr" ]; then
                    echo "$ipv6_addr|ipv6"
                    return 0
                fi
                ;;
            mycelium)
                if [ -n "$mycelium_addr" ]; then
                    echo "$mycelium_addr|mycelium"
                    return 0
                fi
                ;;
            wireguard)
                if [ -n "$wireguard_addr" ]; then
                    echo "$wireguard_addr|wireguard"
                    return 0
                fi
                ;;
        esac
    done

    # No preferred network available, try any available
    [ -n "$ipv4_addr" ] && echo "$ipv4_addr|ipv4" && return 0
    [ -n "$mycelium_addr" ] && echo "$mycelium_addr|mycelium" && return 0
    [ -n "$wireguard_addr" ] && echo "$wireguard_addr|wireguard" && return 0
    [ -n "$ipv6_addr" ] && echo "$ipv6_addr|ipv6" && return 0

    return 1
}

# Legacy compatibility: get_network_preference maps to first item in prefer list
get_network_preference() {
    local app_name="$1"
    local prefer=$(get_deployment_prefer "$app_name")
    echo "$prefer" | cut -d',' -f1
}

# Legacy compatibility: get_global_network_preference
get_global_network_preference() {
    local prefer=$(get_global_prefer)
    echo "$prefer" | cut -d',' -f1
}

# Legacy compatibility: get_global_network_mode maps to provision
get_global_network_mode() {
    get_global_provision
}

# Get appropriate IP address based on network preference (legacy function)
get_deployment_ip() {
    local app_name="$1"
    local state_dir=$(get_app_state_dir "$app_name")
    local state_file="$state_dir/state.yaml"
    local preferred_network=$(get_network_preference "$app_name")

    if [ "$preferred_network" = "mycelium" ]; then
        if command_exists yq; then
            local myc_ip=$(yq eval '.mycelium_address' "$state_file" 2>/dev/null)
            if [ -n "$myc_ip" ] && [ "$myc_ip" != "null" ]; then
                echo "$myc_ip"
                return 0
            fi
        else
            local myc_ip=$(grep "^mycelium_address:" "$state_file" | awk '{print $2}' || echo "")
            if [ -n "$myc_ip" ]; then
                echo "$myc_ip"
                return 0
            fi
        fi
        log_warning "Mycelium IP not available, falling back to ipv4"
    fi

    # Default to ipv4
    if command_exists yq; then
        yq eval '.ipv4_address' "$state_file" 2>/dev/null
    else
        grep "^ipv4_address:" "$state_file" | awk '{print $2}' || echo ""
    fi
}

# Test connectivity to all available networks
test_network_connectivity() {
    local deployment_id="$1"
    local registry_file="$HOME/.config/tfgrid-compose/deployments.yaml"

    if [ ! -f "$registry_file" ]; then
        log_error "No deployments registry found"
        return 1
    fi

    local app_name=$(yq eval ".deployments.\"$deployment_id\".app_name" "$registry_file" 2>/dev/null)

    echo "Testing network connectivity for $app_name ($deployment_id)..."
    echo ""

    # Get all addresses
    local ipv4_addr=$(yq eval ".deployments.\"$deployment_id\".ipv4_address" "$registry_file" 2>/dev/null)
    local ipv6_addr=$(yq eval ".deployments.\"$deployment_id\".ipv6_address" "$registry_file" 2>/dev/null)
    local mycelium_addr=$(yq eval ".deployments.\"$deployment_id\".mycelium_address" "$registry_file" 2>/dev/null)
    local wireguard_addr=$(yq eval ".deployments.\"$deployment_id\".wireguard_address" "$registry_file" 2>/dev/null)

    # Test IPv4
    if [ -n "$ipv4_addr" ] && [ "$ipv4_addr" != "null" ]; then
        echo -n "  IPv4 ($ipv4_addr): "
        if timeout 5 bash -c "echo > /dev/tcp/$ipv4_addr/22" 2>/dev/null; then
            echo "reachable"
        else
            echo "unreachable"
        fi
    fi

    # Test IPv6
    if [ -n "$ipv6_addr" ] && [ "$ipv6_addr" != "null" ]; then
        echo -n "  IPv6 ($ipv6_addr): "
        if timeout 5 bash -c "echo > /dev/tcp/$ipv6_addr/22" 2>/dev/null; then
            echo "reachable"
        else
            echo "unreachable"
        fi
    fi

    # Test Mycelium
    if [ -n "$mycelium_addr" ] && [ "$mycelium_addr" != "null" ]; then
        echo -n "  Mycelium ($mycelium_addr): "
        if ping6 -c 1 -W 2 "$mycelium_addr" >/dev/null 2>&1; then
            echo "reachable"
        else
            echo "unreachable"
        fi
    fi

    # Test WireGuard
    if [ -n "$wireguard_addr" ] && [ "$wireguard_addr" != "null" ]; then
        echo -n "  WireGuard ($wireguard_addr): "
        if timeout 5 bash -c "echo > /dev/tcp/$wireguard_addr/22" 2>/dev/null; then
            echo "reachable"
        else
            echo "unreachable"
        fi
    fi

    echo ""
}

# Network subcommand handler
network_subcommand() {
    local subcommand="${1:-help}"
    shift 2>/dev/null || true

    case "$subcommand" in
        provision)
            local networks="$1"
            if [ -z "$networks" ]; then
                echo ""
                echo "Current provisioning: $(get_global_provision)"
                echo ""
                echo "Usage: tfgrid-compose network provision <networks>"
                echo ""
                echo "Examples:"
                echo "  tfgrid-compose network provision ipv4,mycelium"
                echo "  tfgrid-compose network provision mycelium"
                echo "  tfgrid-compose network provision all"
                echo ""
                echo "Available networks: ipv4, ipv6, mycelium, wireguard, all"
                return 0
            fi
            set_global_provision "$networks"
            ;;

        prefer)
            local networks="$1"
            if [ -z "$networks" ]; then
                echo ""
                echo "Current preference: $(get_global_prefer)"
                echo ""
                echo "Usage: tfgrid-compose network prefer <networks>"
                echo ""
                echo "Networks are tried in order until one succeeds."
                echo ""
                echo "Examples:"
                echo "  tfgrid-compose network prefer mycelium,ipv4"
                echo "  tfgrid-compose network prefer ipv4,mycelium,wireguard"
                echo "  tfgrid-compose network prefer ipv4"
                echo ""
                echo "Available networks: ipv4, ipv6, mycelium, wireguard"
                return 0
            fi
            set_global_prefer "$networks"
            ;;

        get|show)
            echo ""
            echo "Network Settings"
            echo "================"
            echo ""
            echo "Provisioning (networks deployed on VM):"
            echo "  $(get_global_provision)"
            echo ""
            echo "Connection preference (tried in order):"
            echo "  $(get_global_prefer)"
            echo ""

            # Show deployment-specific if context available
            local deployment_id=$(get_smart_context 2>/dev/null)
            if [ -n "$deployment_id" ]; then
                local registry_file="$HOME/.config/tfgrid-compose/deployments.yaml"
                if [ -f "$registry_file" ]; then
                    local app_name=$(yq eval ".deployments.\"$deployment_id\".app_name" "$registry_file" 2>/dev/null)
                    if [ -n "$app_name" ] && [ "$app_name" != "null" ]; then
                        echo "Selected deployment: $app_name ($deployment_id)"
                        local dep_prefer=$(get_deployment_prefer "$deployment_id")
                        echo "  Preference: $dep_prefer"

                        # Show which IP would be used
                        local result=$(get_preferred_ip "$deployment_id")
                        if [ -n "$result" ]; then
                            local ip=$(echo "$result" | cut -d'|' -f1)
                            local net=$(echo "$result" | cut -d'|' -f2)
                            echo "  Active: $ip ($net)"
                        fi
                        echo ""
                    fi
                fi
            fi
            ;;

        list)
            echo ""
            echo "Available Networks"
            echo "=================="
            echo ""
            echo "  mycelium  - Mycelium overlay network (global IPv6, encrypted, recommended)"
            echo "  wireguard - WireGuard VPN (private network, encrypted)"
            echo "  ipv4      - Public IPv4 address (direct internet access)"
            echo "  ipv6      - Public IPv6 address (direct internet access)"
            echo ""
            echo "Use 'all' with provision to enable all networks."
            echo ""
            ;;

        test)
            local deployment_id=$(get_smart_context 2>/dev/null)
            if [ -z "$deployment_id" ]; then
                log_error "No deployment selected. Use 't select' first."
                return 1
            fi
            test_network_connectivity "$deployment_id"
            ;;

        # Legacy compatibility
        mode)
            log_warning "Deprecated: 'network mode' is replaced by 'network provision'"
            local mode="$1"
            if [ -z "$mode" ]; then
                echo "Current: $(get_global_provision)"
                return 0
            fi
            # Convert old mode format to new provision format
            case "$mode" in
                wireguard-only) set_global_provision "ipv4" ;;
                mycelium-only) set_global_provision "mycelium" ;;
                both) set_global_provision "ipv4,mycelium" ;;
                *) set_global_provision "$mode" ;;
            esac
            ;;

        help|*)
            echo ""
            echo "Network Management"
            echo "=================="
            echo ""
            echo "Provisioning (what networks the VM will have):"
            echo "  provision <networks>   Set networks to provision"
            echo "                         Example: t network provision ipv4,mycelium"
            echo ""
            echo "Connection (which network to use, in preference order):"
            echo "  prefer <networks>      Set connection preference order"
            echo "                         Example: t network prefer mycelium,ipv4"
            echo ""
            echo "Information:"
            echo "  get, show              Show current settings"
            echo "  list                   List available networks"
            echo "  test                   Test connectivity to all networks"
            echo ""
            echo "One-off override (for ssh command):"
            echo "  t ssh --ipv4           Force IPv4 for this connection"
            echo "  t ssh --mycelium       Force mycelium for this connection"
            echo "  t ssh --wireguard      Force wireguard for this connection"
            echo "  t ssh --ipv6           Force IPv6 for this connection"
            echo ""
            if [ "$subcommand" != "help" ]; then
                log_error "Unknown subcommand: $subcommand"
                return 1
            fi
            ;;
    esac
}
