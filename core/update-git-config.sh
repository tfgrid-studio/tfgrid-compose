#!/usr/bin/env bash
# TFGrid Compose - Update Git Config Module
# Updates git configuration on running VMs

# Source dependencies
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/deployment-id.sh"

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
    
    # Resolve app name to deployment ID via registry
    local deployment_id=$(resolve_deployment "$app_name")
    if [ -z "$deployment_id" ]; then
        log_error "No deployment found for: $app_name"
        echo ""
        echo "Deploy first with: tfgrid-compose up $app_name"
        echo ""
        return 1
    fi
    
    local state_dir="$base_dir/$deployment_id"
    
    if [ ! -d "$state_dir" ]; then
        log_error "Deployment state not found (inconsistent state)"
        echo ""
        echo "Try redeploying: tfgrid-compose up $app_name --force"
        echo ""
        return 1
    fi
    
    # Get VM IP
    local ipv4_address=$(grep "^ipv4_address:" "$state_dir/state.yaml" 2>/dev/null | awk '{print $2}')
    
    if [ -z "$ipv4_address" ]; then
        log_error "No VM IP found for $app_name"
        return 1
    fi
    
    log_info "Connecting to VM: $ipv4_address"
    echo ""
    
    # Update git config on the VM
    log_info "Updating git configuration..."
    
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        root@$ipv4_address "su - developer -c \"git config --global user.name '$TFGRID_GIT_NAME' && git config --global user.email '$TFGRID_GIT_EMAIL'\""; then
        
        echo ""
        log_success "✅ Git configuration updated!"
        echo ""
        echo "Verification:"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$ipv4_address "su - developer -c 'git config --global user.name && git config --global user.email'" 2>/dev/null | while read line; do
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
