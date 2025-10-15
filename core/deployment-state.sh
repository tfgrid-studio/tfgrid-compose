#!/usr/bin/env bash
# TFGrid Compose - Deployment State Module
# Handles multi-app deployment state management

# State configuration
STATE_BASE_DIR="$HOME/.config/tfgrid-compose/state"
CURRENT_APP_FILE="$HOME/.config/tfgrid-compose/current-app"

# Ensure state directory exists
ensure_state_dir() {
    mkdir -p "$STATE_BASE_DIR"
}

# Get state directory for an app
get_app_state_dir() {
    local app_name="$1"
    echo "$STATE_BASE_DIR/$app_name"
}

# Check if app is deployed
is_app_deployed() {
    local app_name="$1"
    local state_dir=$(get_app_state_dir "$app_name")
    
    [ -f "$state_dir/vm_ip" ]
}

# Get current active app
get_current_app() {
    if [ -f "$CURRENT_APP_FILE" ]; then
        cat "$CURRENT_APP_FILE"
    fi
}

# Set current active app
set_current_app() {
    local app_name="$1"
    
    # Verify app is deployed
    if ! is_app_deployed "$app_name"; then
        log_error "Cannot switch to $app_name: not deployed"
        return 1
    fi
    
    echo "$app_name" > "$CURRENT_APP_FILE"
    return 0
}

# List all deployed apps
list_deployed_apps() {
    ensure_state_dir
    
    local current_app=$(get_current_app)
    local found_any=0
    
    if [ ! "$(ls -A $STATE_BASE_DIR 2>/dev/null)" ]; then
        return 0
    fi
    
    for state_dir in "$STATE_BASE_DIR"/*; do
        if [ -d "$state_dir" ] && [ -f "$state_dir/vm_ip" ]; then
            local app_name=$(basename "$state_dir")
            found_any=1
            
            if [ "$app_name" = "$current_app" ]; then
                echo "  * $app_name (active)"
            else
                echo "    $app_name"
            fi
        fi
    done
    
    return $found_any
}

# Initialize deployment state for an app
init_deployment_state() {
    local app_name="$1"
    local state_dir=$(get_app_state_dir "$app_name")
    
    ensure_state_dir
    mkdir -p "$state_dir"
    
    # Set as current app
    set_current_app "$app_name"
}

# Clean deployment state for an app
clean_deployment_state() {
    local app_name="$1"
    local state_dir=$(get_app_state_dir "$app_name")
    
    if [ -d "$state_dir" ]; then
        rm -rf "$state_dir"
        
        # Clear current app if it was this one
        local current_app=$(get_current_app)
        if [ "$current_app" = "$app_name" ]; then
            rm -f "$CURRENT_APP_FILE"
        fi
    fi
}

# Get app state value
get_app_state() {
    local app_name="$1"
    local key="$2"
    local state_dir=$(get_app_state_dir "$app_name")
    
    if [ -f "$state_dir/$key" ]; then
        cat "$state_dir/$key"
    fi
}

# Set app state value
set_app_state() {
    local app_name="$1"
    local key="$2"
    local value="$3"
    local state_dir=$(get_app_state_dir "$app_name")
    
    mkdir -p "$state_dir"
    echo "$value" > "$state_dir/$key"
}

# Export state directory for legacy compatibility
export_app_state_dir() {
    local app_name="$1"
    export STATE_DIR=$(get_app_state_dir "$app_name")
}
