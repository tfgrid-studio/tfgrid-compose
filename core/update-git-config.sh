#!/usr/bin/env bash
# TFGrid Compose - Update Git Config Module
# Updates git configuration on running VMs

# Update git config on a deployed app
update_git_config() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        log_error "App name required"
        echo ""
        echo "Usage: tfgrid-compose update-git-config <app-name>"
        echo ""
        echo "Example:"
        echo "  tfgrid-compose update-git-config tfgrid-ai-agent"
        echo ""
        return 1
    fi
    
    echo ""
    log_info "Updating git configuration for: $app_name"
    echo ""
    
    # Load credentials
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        log_error "No credentials found"
        echo ""
        echo "Run 'tfgrid-compose login' first to set git identity"
        return 1
    fi
    
    source "$DEPLOYER_ROOT/core/login.sh"
    load_credentials
    
    # Check if git config is set
    if [ -z "$TFGRID_GIT_NAME" ] || [ -z "$TFGRID_GIT_EMAIL" ]; then
        log_error "Git identity not configured"
        echo ""
        echo "Run 'tfgrid-compose login' to add git identity"
        echo "(Select option 1 to add missing credentials)"
        return 1
    fi
    
    log_info "Using git identity from login:"
    echo "  Name:  $TFGRID_GIT_NAME"
    echo "  Email: $TFGRID_GIT_EMAIL"
    echo ""
    
    # Get deployment state
    local base_dir="${STATE_BASE_DIR:-$HOME/.config/tfgrid-compose/state}"
    local state_dir="$base_dir/$app_name"
    
    if [ ! -d "$state_dir" ]; then
        log_error "No deployment found for: $app_name"
        echo ""
        echo "Available deployments:"
        tfgrid-compose list
        return 1
    fi
    
    # Get VM IP
    local vm_ip=$(grep "^vm_ip:" "$state_dir/state.yaml" 2>/dev/null | awk '{print $2}')
    
    if [ -z "$vm_ip" ]; then
        log_error "No VM IP found for $app_name"
        return 1
    fi
    
    log_info "Connecting to VM: $vm_ip"
    echo ""
    
    # Update git config on the VM
    log_info "Updating git configuration..."
    
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        root@$vm_ip "su - developer -c \"git config --global user.name '$TFGRID_GIT_NAME' && git config --global user.email '$TFGRID_GIT_EMAIL'\""; then
        
        echo ""
        log_success "✅ Git configuration updated!"
        echo ""
        echo "Verification:"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "su - developer -c 'git config --global user.name && git config --global user.email'" 2>/dev/null | while read line; do
            echo "  $line"
        done
        echo ""
        
        return 0
    else
        log_error "Failed to update git configuration"
        return 1
    fi
}

# Export function
export -f update_git_config
