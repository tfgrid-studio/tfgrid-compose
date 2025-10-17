#!/usr/bin/env bash
# Interactive Configuration Mode
# Guides users through deployment configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/node-selector.sh"

# Run interactive configuration
run_interactive_config() {
    echo ""
    log_info "Interactive Configuration"
    echo ""
    
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
    echo "   Node: $selected_node"
    echo "   Resources: $final_cpu CPU, ${final_mem}MB RAM, ${final_disk}GB disk"
    echo "   Network: $final_network"
    echo ""
    
    # Export variables for use in orchestrator
    export SELECTED_NODE_ID="$selected_node"
    export SELECTED_CPU="$final_cpu"
    export SELECTED_MEM="$final_mem"
    export SELECTED_DISK="$final_disk"
    export SELECTED_NETWORK="$final_network"
    
    return 0
}
