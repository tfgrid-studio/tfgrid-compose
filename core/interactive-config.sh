#!/usr/bin/env bash
# Interactive Configuration Mode
# Guides users through deployment configuration with app-specific environment variables

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/node-selector.sh"
source "$SCRIPT_DIR/dns-automation.sh"

# Associative array to store collected environment variables
declare -A COLLECTED_ENV_VARS

# Prompt for a single environment variable
# Returns the value via stdout
prompt_env_var() {
    local name="$1"
    local description="$2"
    local required="$3"
    local default="$4"
    local secret="$5"
    local options="$6"
    
    local prompt_text="  $description"
    if [ -n "$default" ]; then
        prompt_text="$prompt_text [$default]"
    fi
    prompt_text="$prompt_text: "
    
    local value=""
    
    # Handle options (select from list)
    if [ -n "$options" ]; then
        echo "  $description:"
        
        # Split options by comma into array
        local opt_array=()
        IFS=',' read -ra opt_array <<< "$options"
        
        # Display options
        local i=1
        for opt in "${opt_array[@]}"; do
            opt=$(echo "$opt" | xargs)  # Trim whitespace
            if [ "$opt" = "$default" ]; then
                echo "    $i) $opt (default)"
            else
                echo "    $i) $opt"
            fi
            ((i++))
        done
        echo ""
        
        read -p "  Choose [1]: " choice
        choice=${choice:-1}
        
        # Convert choice to value
        local idx=$((choice - 1))
        value="${opt_array[$idx]}"
        value=$(echo "$value" | xargs)  # Trim whitespace
    elif [ "$secret" = "true" ]; then
        # Secret input (hidden)
        read -s -p "$prompt_text" value
        echo ""  # New line after hidden input
    else
        # Regular input
        read -p "$prompt_text" value
    fi
    
    # Apply default if empty
    if [ -z "$value" ] && [ -n "$default" ]; then
        value="$default"
    fi
    
    # Validate required
    if [ "$required" = "true" ] && [ -z "$value" ]; then
        log_error "$name is required"
        return 1
    fi
    
    echo "$value"
}

# Parse environment variables from manifest and prompt user
collect_app_environment() {
    local manifest="$1"
    
    # Check if manifest has environment section
    if ! yq eval '.environment' "$manifest" 2>/dev/null | grep -q "name:"; then
        return 0  # No environment variables defined
    fi
    
    echo ""
    echo "→ Application Configuration"
    echo ""
    
    # Get number of environment variables
    local env_count=$(yq eval '.environment | length' "$manifest" 2>/dev/null || echo "0")
    
    if [ "$env_count" = "0" ] || [ "$env_count" = "null" ]; then
        return 0
    fi
    
    # Iterate through environment variables
    for ((i=0; i<env_count; i++)); do
        local name=$(yq eval ".environment[$i].name" "$manifest" 2>/dev/null)
        local description=$(yq eval ".environment[$i].description" "$manifest" 2>/dev/null)
        local required=$(yq eval ".environment[$i].required" "$manifest" 2>/dev/null)
        local default=$(yq eval ".environment[$i].default" "$manifest" 2>/dev/null)
        local secret=$(yq eval ".environment[$i].secret" "$manifest" 2>/dev/null)
        local options=$(yq eval ".environment[$i].options | join(\",\")" "$manifest" 2>/dev/null | tr -d '\n')
        local depends_on=$(yq eval ".environment[$i].depends_on" "$manifest" 2>/dev/null)
        
        # Clean up null values
        [ "$name" = "null" ] && continue
        [ "$description" = "null" ] && description="$name"
        [ "$required" = "null" ] && required="false"
        [ "$default" = "null" ] && default=""
        [ "$secret" = "null" ] && secret="false"
        [ "$options" = "null" ] && options=""
        [ "$depends_on" = "null" ] && depends_on=""
        
        # Check dependencies
        if [ -n "$depends_on" ]; then
            local dep_key=$(echo "$depends_on" | yq eval 'keys | .[0]' - 2>/dev/null)
            local dep_value=$(echo "$depends_on" | yq eval ".$dep_key" - 2>/dev/null)
            
            if [ -n "$dep_key" ] && [ -n "$dep_value" ]; then
                local current_value="${COLLECTED_ENV_VARS[$dep_key]}"
                if [ "$current_value" != "$dep_value" ]; then
                    continue  # Skip this variable, dependency not met
                fi
            fi
        fi
        
        # Prompt for value
        local value
        value=$(prompt_env_var "$name" "$description" "$required" "$default" "$secret" "$options")
        local result=$?
        
        if [ $result -ne 0 ]; then
            return 1
        fi
        
        # Store in associative array
        COLLECTED_ENV_VARS["$name"]="$value"
        
        # Handle DNS provider selection
        if [ "$name" = "DNS_PROVIDER" ] && [ -n "$value" ] && [ "$value" != "manual" ]; then
            echo ""
            if ! configure_dns_provider "$value"; then
                log_warning "DNS configuration skipped, you'll need to set up DNS manually"
            fi
        fi
    done
    
    echo ""
    return 0
}

# Export collected environment variables
export_collected_env_vars() {
    for key in "${!COLLECTED_ENV_VARS[@]}"; do
        export "$key"="${COLLECTED_ENV_VARS[$key]}"
    done
}

# Run interactive configuration
run_interactive_config() {
    echo ""
    log_info "🚀 Interactive Configuration for $APP_NAME"
    echo ""
    
    # Phase 1: App-specific environment variables
    if ! collect_app_environment "$APP_MANIFEST"; then
        return 1
    fi
    
    # Get manifest defaults
    local default_cpu=$(yaml_get "$APP_MANIFEST" "resources.cpu" || echo "2")
    local default_mem=$(yaml_get "$APP_MANIFEST" "resources.memory" || echo "4096")
    local default_disk=$(yaml_get "$APP_MANIFEST" "resources.disk" || echo "50")
    
    # Show defaults
    echo "→ Resources Configuration"
    echo "  Default specs (from $APP_NAME manifest):"
    echo "    CPU: $default_cpu cores"
    echo "    Memory: $default_mem MB"
    echo "    Disk: $default_disk GB"
    echo ""
    
    # Ask if user wants to customize
    read -p "  Customize resources? (y/N): " -n 1 -r customize
    echo ""
    echo ""
    
    local final_cpu=$default_cpu
    local final_mem=$default_mem
    local final_disk=$default_disk
    
    if [[ $customize =~ ^[Yy]$ ]]; then
        read -p "  CPU cores [$default_cpu]: " input_cpu
        final_cpu=${input_cpu:-$default_cpu}
        
        read -p "  Memory MB [$default_mem]: " input_mem
        final_mem=${input_mem:-$default_mem}
        
        read -p "  Disk GB [$default_disk]: " input_disk
        final_disk=${input_disk:-$default_disk}
        echo ""
    fi
    
    # Node selection
    echo "→ Node Selection"
    echo "  1. Auto-select best available node (recommended)"
    echo "  2. Browse available nodes"
    echo "  3. Enter specific node ID"
    echo ""
    read -p "  Choose (1-3) [1]: " node_choice
    node_choice=${node_choice:-1}
    echo ""
    
    local selected_node=""
    
    case $node_choice in
        1)
            # Auto-select
            log_info "Auto-selecting best node..."
            echo ""
            selected_node=$(select_best_node "$final_cpu" "$final_mem" "$final_disk")
            if [ -z "$selected_node" ] || [ "$selected_node" = "null" ]; then
                log_error "Failed to auto-select node"
                return 1
            fi
            ;;
        2)
            # Browse nodes
            local nodes_json=$(show_available_nodes "$final_cpu" "$final_mem" "$final_disk")
            if [ $? -ne 0 ]; then
                return 1
            fi
            
            read -p "  Select node (number, or 'a' for auto): " selection
            
            if [ "$selection" = "a" ]; then
                selected_node=$(select_best_node "$final_cpu" "$final_mem" "$final_disk")
            else
                selected_node=$(get_node_from_list "$selection" "$nodes_json")
            fi
            
            if [ -z "$selected_node" ] || [ "$selected_node" = "null" ]; then
                log_error "Invalid selection"
                return 1
            fi
            
            echo ""
            log_success "Selected node: $selected_node"
            echo ""
            ;;
        3)
            # Manual entry
            read -p "  Enter node ID: " selected_node
            if [ -z "$selected_node" ]; then
                log_error "Node ID cannot be empty"
                return 1
            fi
            echo ""
            
            # Verify node exists
            if ! verify_node_exists "$selected_node"; then
                return 1
            fi
            ;;
        *)
            log_error "Invalid choice"
            return 1
            ;;
    esac
    
    # Network selection
    echo "→ Network"
    read -p "  Network (main/test/dev) [main]: " network_input
    local final_network=${network_input:-main}
    echo ""
    
    # Summary
    log_success "Configuration complete!"
    echo ""
    
    # Show app-specific configuration if any
    if [ ${#COLLECTED_ENV_VARS[@]} -gt 0 ]; then
        echo "   App Configuration:"
        for key in "${!COLLECTED_ENV_VARS[@]}"; do
            local value="${COLLECTED_ENV_VARS[$key]}"
            # Mask secrets
            if [[ "$key" =~ (PASSWORD|TOKEN|KEY|SECRET) ]]; then
                value="********"
            fi
            echo "     $key: $value"
        done
        echo ""
    fi
    
    echo "   Node: $selected_node"
    echo "   Resources: $final_cpu CPU, ${final_mem}MB RAM, ${final_disk}GB disk"
    echo "   Network: $final_network"
    echo ""
    
    # Confirm before proceeding
    read -p "Proceed with deployment? (Y/n): " confirm
    confirm=${confirm:-Y}
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        return 1
    fi
    echo ""
    
    # Export variables for use in orchestrator
    export SELECTED_NODE_ID="$selected_node"
    export SELECTED_CPU="$final_cpu"
    export SELECTED_MEM="$final_mem"
    export SELECTED_DISK="$final_disk"
    export SELECTED_NETWORK="$final_network"
    
    # Export collected app environment variables
    export_collected_env_vars
    
    return 0
}
