#!/usr/bin/env bash
# Orchestrator - Main deployment logic that coordinates everything

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/pattern-loader.sh"
source "$SCRIPT_DIR/app-loader.sh"
source "$SCRIPT_DIR/node-selector.sh"
source "$SCRIPT_DIR/interactive-config.sh"

# Cleanup on deployment error
cleanup_on_error() {
    local app_name="$1"
    log_warning "Deployment failed, cleaning up partial state..."
    
    # Don't clean if user wants to debug
    if [ "${TFGRID_DEBUG:-}" = "1" ]; then
        log_info "Debug mode: Keeping state for inspection"
        return 0
    fi
    
    # Clean stale state to allow retry
    clean_stale_state "$app_name"
    log_info "State cleaned. You can retry deployment."
}

# Deploy application
deploy_app() {
    log_step "Starting deployment orchestration..."
    echo ""
    
    # Setup error trap
    trap 'cleanup_on_error "$APP_NAME"' ERR
    
    # Source .env from app directory if it exists
    if [ -f "$APP_DIR/.env" ]; then
        log_info "Loading configuration from $APP_DIR/.env"
        source "$APP_DIR/.env"
    else
        log_warning "No .env found in app directory"
        log_info "Run: tfgrid-compose init <app> to create one"
    fi
    
    # Validate prerequisites
    if ! check_requirements; then
        log_error "Prerequisites not met"
        return 1
    fi
    
    # State directory already created by init_deployment_state in CLI
    # Verify STATE_DIR is set
    if [ -z "$STATE_DIR" ]; then
        log_error "STATE_DIR not set - internal error"
        return 1
    fi
    
    log_info "Using state directory: $STATE_DIR"
    
    # === Node & Resource Selection ===
    echo ""
    log_step "Configuring deployment..."
    echo ""
    
    # Determine resources (priority: flags > .env > manifest > defaults)
    # Try recommended first, fallback to min, then default
    MANIFEST_CPU=$(yaml_get "$APP_MANIFEST" "resources.cpu.recommended" || yaml_get "$APP_MANIFEST" "resources.cpu.min" || echo "2")
    MANIFEST_MEM=$(yaml_get "$APP_MANIFEST" "resources.memory.recommended" || yaml_get "$APP_MANIFEST" "resources.memory.min" || echo "4096")
    MANIFEST_DISK=$(yaml_get "$APP_MANIFEST" "resources.disk.recommended" || yaml_get "$APP_MANIFEST" "resources.disk.min" || echo "50")
    
    DEPLOY_CPU=${CUSTOM_CPU:-${TF_VAR_ai_agent_cpu:-$MANIFEST_CPU}}
    DEPLOY_MEM=${CUSTOM_MEM:-${TF_VAR_ai_agent_mem:-$MANIFEST_MEM}}
    DEPLOY_DISK=${CUSTOM_DISK:-${TF_VAR_ai_agent_disk:-$MANIFEST_DISK}}
    DEPLOY_NETWORK=${CUSTOM_NETWORK:-${TF_VAR_tfgrid_network:-"main"}}
    
    # Interactive mode
    if [ "$INTERACTIVE_MODE" = "true" ]; then
        log_info "Running interactive configuration..."
        if ! run_interactive_config; then
            log_error "Interactive configuration cancelled"
            return 1
        fi
        
        # Use values from interactive config
        DEPLOY_NODE=${SELECTED_NODE_ID}
        DEPLOY_CPU=${SELECTED_CPU}
        DEPLOY_MEM=${SELECTED_MEM}
        DEPLOY_DISK=${SELECTED_DISK}
        DEPLOY_NETWORK=${SELECTED_NETWORK}
    else
        # Non-interactive: Use custom node or auto-select
        if [ -n "$CUSTOM_NODE" ] && [ "$CUSTOM_NODE" != "" ]; then
            # Verify custom node
            log_info "Using specified node: $CUSTOM_NODE"
            echo ""
            if ! verify_node_exists "$CUSTOM_NODE"; then
                return 1
            fi
            DEPLOY_NODE=$CUSTOM_NODE
        else
            # Auto-select via GridProxy
            log_info "Resources: $DEPLOY_CPU CPU, ${DEPLOY_MEM}MB RAM, ${DEPLOY_DISK}GB disk"
            log_info "Auto-selecting best available node..."
            echo ""
            DEPLOY_NODE=$(select_best_node "$DEPLOY_CPU" "$DEPLOY_MEM" "$DEPLOY_DISK" "$DEPLOY_NETWORK")
            # Clean any whitespace/newlines from node ID
            DEPLOY_NODE=$(echo "$DEPLOY_NODE" | tr -d '[:space:]')
            if [ -z "$DEPLOY_NODE" ] || [ "$DEPLOY_NODE" = "null" ]; then
                log_error "Failed to select node"
                echo ""
                echo "Try:"
                echo "  - Use interactive mode: tfgrid-compose up $APP_NAME -i"
                echo "  - Specify node manually: tfgrid-compose up $APP_NAME --node <id>"
                echo "  - Browse available nodes: https://dashboard.grid.tf"
                return 1
            fi
        fi
    fi
    
    # Ensure all values are clean integers (remove any whitespace/newlines)
    DEPLOY_NODE=$(echo "$DEPLOY_NODE" | tr -d '[:space:]')
    DEPLOY_CPU=$(echo "$DEPLOY_CPU" | tr -d '[:space:]')
    DEPLOY_MEM=$(echo "$DEPLOY_MEM" | tr -d '[:space:]')
    DEPLOY_DISK=$(echo "$DEPLOY_DISK" | tr -d '[:space:]')
    
    # Export Terraform variables based on pattern
    export TF_VAR_tfgrid_network=$DEPLOY_NETWORK
    
    # Pattern-specific variable mapping
    case "$PATTERN_NAME" in
        single-vm)
            # Single-VM pattern
            export TF_VAR_vm_node=$DEPLOY_NODE
            export TF_VAR_vm_cpu=$DEPLOY_CPU
            export TF_VAR_vm_mem=$DEPLOY_MEM
            export TF_VAR_vm_disk=$DEPLOY_DISK
            log_info "Exporting single-vm variables: node=$DEPLOY_NODE, cpu=$DEPLOY_CPU, mem=$DEPLOY_MEM, disk=$DEPLOY_DISK"
            ;;
        gateway)
            # Gateway pattern (for now, use single node for gateway)
            export TF_VAR_gateway_node=$DEPLOY_NODE
            export TF_VAR_gateway_cpu=$DEPLOY_CPU
            export TF_VAR_gateway_mem=$DEPLOY_MEM
            export TF_VAR_gateway_disk=$DEPLOY_DISK
            # Backend nodes would need additional selection logic
            log_warning "Gateway pattern: Using single node for gateway. Multi-node selection coming in v0.11.0"
            ;;
        k3s)
            # K3s pattern (for now, use single node for management)
            export TF_VAR_management_node=$DEPLOY_NODE
            export TF_VAR_management_cpu=$DEPLOY_CPU
            export TF_VAR_management_mem=$DEPLOY_MEM
            export TF_VAR_management_disk=$DEPLOY_DISK
            log_warning "K3s pattern: Using single node for management. Multi-node selection coming in v0.11.0"
            ;;
        *)
            # Unknown pattern - export generic variables
            export TF_VAR_vm_node=$DEPLOY_NODE
            export TF_VAR_vm_cpu=$DEPLOY_CPU
            export TF_VAR_vm_mem=$DEPLOY_MEM
            export TF_VAR_vm_disk=$DEPLOY_DISK
            log_warning "Unknown pattern '$PATTERN_NAME', using generic vm_* variables"
            ;;
    esac
    
    log_success "Configuration complete"
    echo ""
    
    # Save deployment metadata
    log_step "Saving deployment metadata..."
    cat > "$STATE_DIR/state.yaml" << EOF
# TFGrid Compose Deployment State
deployed_at: $(date -Iseconds)
app_name: $APP_NAME
app_version: $APP_VERSION
app_dir: $APP_DIR
pattern_name: $PATTERN_NAME
pattern_version: $PATTERN_VERSION
EOF
    
    log_success "Metadata saved"
    echo ""
    
    # Step 1: Generate Terraform configuration
    if ! generate_terraform_config; then
        log_error "Failed to generate Terraform configuration"
        return 1
    fi
    
    # Step 2: Run Terraform
    # Ensure STATE_DIR is exported for subprocess
    export STATE_DIR
    if ! bash "$DEPLOYER_ROOT/core/tasks/terraform.sh"; then
        log_error "Terraform deployment failed"
        return 1
    fi
    
    # Step 2.5: Setup WireGuard (if needed)
    if ! bash "$DEPLOYER_ROOT/core/tasks/wireguard.sh"; then
        log_error "WireGuard setup failed"
        return 1
    fi
    
    # Step 2.6: Wait for SSH to be ready
    echo ""
    if ! bash "$DEPLOYER_ROOT/core/wait-ssh.sh"; then
        log_warning "SSH check timed out, but continuing..."
        log_info "Deployment may fail if VM is not ready"
    fi
    
    # Step 3: Generate Ansible inventory
    if ! bash "$DEPLOYER_ROOT/core/tasks/inventory.sh"; then
        log_error "Failed to generate Ansible inventory"
        return 1
    fi
    
    # Step 4: Run Ansible
    # First copy pattern platform to state directory
    cp -r "$PATTERN_PLATFORM_DIR" "$STATE_DIR/ansible"
    if ! bash "$DEPLOYER_ROOT/core/tasks/ansible.sh"; then
        log_error "Ansible configuration failed"
        return 1
    fi
    
    # Step 5: Deploy app source code
    if ! deploy_app_source; then
        log_error "Failed to deploy app source"
        return 1
    fi
    
    # Step 6: Run app hooks
    if ! run_app_hooks; then
        log_error "App deployment hooks failed"
        return 1
    fi
    
    # Step 7: Verify deployment
    if ! verify_deployment; then
        log_warning "Deployment verification had issues"
    fi
    
    echo ""
    log_success "🎉 Deployment complete!"
    echo ""
    log_info "App: $APP_NAME v$APP_VERSION"
    log_info "Pattern: $PATTERN_NAME v$PATTERN_VERSION"
    echo ""
    log_info "Next steps:"
    echo "  • Check status: tfgrid-compose status $APP_NAME"
    echo "  • View logs: tfgrid-compose logs $APP_NAME"
    echo "  • Connect: tfgrid-compose ssh $APP_NAME"
    echo ""
    
    # Disable error trap on success
    trap - ERR
    
    return 0
}

# Generate Terraform configuration
generate_terraform_config() {
    log_step "Generating Terraform configuration..."
    
    # Parse manifest configuration and export as Terraform variables
    log_info "Parsing manifest configuration..."
    
    # Parse nodes configuration
    local gateway_nodes=$(yaml_get "$APP_MANIFEST" "nodes.gateway")
    local backend_nodes=$(yaml_get "$APP_MANIFEST" "nodes.backend")
    local vm_node=$(yaml_get "$APP_MANIFEST" "nodes.vm")
    
    # Gateway pattern nodes
    if [ -n "$gateway_nodes" ]; then
        # Handle single node or array format
        if [[ "$gateway_nodes" == "["* ]]; then
            export TF_VAR_gateway_node=$(echo "$gateway_nodes" | tr -d '[]' | awk '{print $1}' | tr -d ',')
        else
            export TF_VAR_gateway_node="$gateway_nodes"
        fi
        log_info "Gateway node: $TF_VAR_gateway_node"
    fi
    
    if [ -n "$backend_nodes" ]; then
        export TF_VAR_internal_nodes="$backend_nodes"
        log_info "Backend nodes: $TF_VAR_internal_nodes"
    fi
    
    # Single-VM pattern nodes (only if not already set from node selection)
    if [ -z "$TF_VAR_vm_node" ] && [ -n "$vm_node" ]; then
        export TF_VAR_vm_node="$vm_node"
        log_info "VM node: $TF_VAR_vm_node"
    fi
    
    # Parse resources configuration
    local gateway_cpu=$(yaml_get "$APP_MANIFEST" "resources.gateway.cpu")
    local gateway_mem=$(yaml_get "$APP_MANIFEST" "resources.gateway.memory")
    local gateway_disk=$(yaml_get "$APP_MANIFEST" "resources.gateway.disk")
    local backend_cpu=$(yaml_get "$APP_MANIFEST" "resources.backend.cpu")
    local backend_mem=$(yaml_get "$APP_MANIFEST" "resources.backend.memory")
    local backend_disk=$(yaml_get "$APP_MANIFEST" "resources.backend.disk")
    local vm_cpu=$(yaml_get "$APP_MANIFEST" "resources.vm.cpu")
    local vm_mem=$(yaml_get "$APP_MANIFEST" "resources.vm.memory")
    local vm_disk=$(yaml_get "$APP_MANIFEST" "resources.vm.disk")
    
    # Export gateway resources
    [ -n "$gateway_cpu" ] && export TF_VAR_gateway_cpu="$gateway_cpu"
    [ -n "$gateway_mem" ] && export TF_VAR_gateway_mem="$gateway_mem"
    [ -n "$gateway_disk" ] && export TF_VAR_gateway_disk="$gateway_disk"
    
    # Export backend resources  
    [ -n "$backend_cpu" ] && export TF_VAR_internal_cpu="$backend_cpu"
    [ -n "$backend_mem" ] && export TF_VAR_internal_mem="$backend_mem"
    [ -n "$backend_disk" ] && export TF_VAR_internal_disk="$backend_disk"
    
    # Export single-VM resources ONLY if not already set (from node selection)
    # This prevents overwriting the values we set earlier based on auto-selection
    [ -z "$TF_VAR_vm_cpu" ] && [ -n "$vm_cpu" ] && export TF_VAR_vm_cpu="$vm_cpu"
    [ -z "$TF_VAR_vm_mem" ] && [ -n "$vm_mem" ] && export TF_VAR_vm_mem="$vm_mem"
    [ -z "$TF_VAR_vm_disk" ] && [ -n "$vm_disk" ] && export TF_VAR_vm_disk="$vm_disk"
    
    # Log resources based on pattern
    if [ -n "$gateway_cpu" ]; then
        log_info "Resources: Gateway(CPU=$gateway_cpu, Mem=$gateway_mem MB, Disk=$gateway_disk GB)"
    fi
    if [ -n "$backend_cpu" ]; then
        log_info "Resources: Backend(CPU=$backend_cpu, Mem=$backend_mem MB, Disk=$backend_disk GB)"
    fi
    if [ -n "$vm_cpu" ]; then
        log_info "Resources: VM(CPU=$vm_cpu, Mem=$vm_mem MB, Disk=$vm_disk GB)"
    fi
    
    # Parse gateway configuration
    local gateway_mode=$(yaml_get "$APP_MANIFEST" "gateway.mode")
    local gateway_domains=$(yaml_get "$APP_MANIFEST" "gateway.domains")
    local ssl_enabled=$(yaml_get "$APP_MANIFEST" "gateway.ssl.enabled")
    local ssl_email=$(yaml_get "$APP_MANIFEST" "gateway.ssl.email")
    
    # Export gateway configuration as environment variables (for Ansible)
    [ -n "$gateway_mode" ] && export GATEWAY_TYPE="gateway_${gateway_mode}"
    [ -n "$ssl_enabled" ] && [ "$ssl_enabled" = "true" ] && export ENABLE_SSL="true"
    [ -n "$ssl_email" ] && export SSL_EMAIL="$ssl_email"
    
    # Parse first domain from domains array
    if [ -n "$gateway_domains" ]; then
        local first_domain=$(echo "$gateway_domains" | grep -o '[a-zA-Z0-9.-]*\.[a-zA-Z]\{2,\}' | head -1)
        [ -n "$first_domain" ] && export DOMAIN_NAME="$first_domain"
        log_info "Domain: $DOMAIN_NAME (SSL: ${ENABLE_SSL:-false})"
    fi
    
    # Parse backend configuration
    local backend_count=$(yaml_get "$APP_MANIFEST" "backend.count")
    [ -n "$backend_count" ] && log_info "Backend VMs: $backend_count"
    
    # Parse network configuration from manifest
    local main_network=$(yaml_get "$APP_MANIFEST" "network.main")
    local inter_node_network=$(yaml_get "$APP_MANIFEST" "network.inter_node")
    local network_mode=$(yaml_get "$APP_MANIFEST" "network.mode")
    
    # Export network configuration (use manifest values or defaults)
    export TF_VAR_tfgrid_network="${TF_VAR_tfgrid_network:-main}"
    export MAIN_NETWORK="${main_network:-${MAIN_NETWORK:-wireguard}}"
    export INTER_NODE_NETWORK="${inter_node_network:-${INTER_NODE_NETWORK:-wireguard}}"
    export NETWORK_MODE="${network_mode:-${NETWORK_MODE:-wireguard-only}}"
    
    # Pass main_network to Terraform
    export TF_VAR_main_network="$MAIN_NETWORK"
    
    log_info "Network: Main=$MAIN_NETWORK, InterNode=$INTER_NODE_NETWORK, Mode=$NETWORK_MODE"
    
    # Copy pattern infrastructure to state directory
    cp -r "$PATTERN_INFRASTRUCTURE_DIR" "$STATE_DIR/terraform"
    
    log_success "Configuration parsed from manifest"
    return 0
}

# Deploy app source code to VM
deploy_app_source() {
    log_step "Deploying application source code..."
    
    local vm_ip=$(state_get "vm_ip")
    
    if [ -z "$vm_ip" ]; then
        log_error "No VM IP found"
        return 1
    fi
    
    log_info "Preparing VM for app deployment..."
    # Create deployment directory on VM
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        root@$vm_ip "mkdir -p /tmp/app-deployment"
    
    # Copy app deployment files to VM
    log_info "Copying deployment hooks..."
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        "$APP_DEPLOYMENT_DIR"/*.sh root@$vm_ip:/tmp/app-deployment/ > /dev/null 2>&1
    return 0
}

# Run app deployment hooks
run_app_hooks() {
    log_step "Running application deployment hooks..."
    
    local vm_ip=$(state_get "vm_ip")
    
    if [ -z "$vm_ip" ]; then
        log_error "No VM IP found"
        return 1
    fi
    
    # Check if Ansible playbook exists (Option B: Ansible deployment)
    if [ -f "$APP_DIR/deployment/playbook.yml" ]; then
        log_info "Detected Ansible playbook deployment"
        
        # Run Ansible playbook
        if ! ansible-playbook -i "$STATE_DIR/inventory.ini" "$APP_DIR/deployment/playbook.yml" \
            > "$STATE_DIR/ansible-app.log" 2>&1; then
            log_error "Ansible playbook failed. Check: $STATE_DIR/ansible-app.log"
            cat "$STATE_DIR/ansible-app.log"
            return 1
        fi
        log_success "Ansible deployment complete"
        return 0
    fi
    
    # Default: Bash hook scripts (Option A: Bash deployment)
    log_info "Using bash hook scripts deployment"
    
    # Hook 1: setup.sh
    log_info "Running setup hook..."
    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        root@$vm_ip "cd /tmp/app-deployment && chmod +x setup.sh && ./setup.sh" > "$STATE_DIR/hook-setup.log" 2>&1; then
        log_error "Setup hook failed. Check: $STATE_DIR/hook-setup.log"
        cat "$STATE_DIR/hook-setup.log"
        return 1
    fi
    log_success "Setup complete"
    
    # Hook 2: configure.sh
    log_info "Running configure hook..."
    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        root@$vm_ip "cd /tmp/app-deployment && chmod +x configure.sh && ./configure.sh" > "$STATE_DIR/hook-configure.log" 2>&1; then
        log_error "Configure hook failed. Check: $STATE_DIR/hook-configure.log"
        cat "$STATE_DIR/hook-configure.log"
        return 1
    fi
    log_success "Configuration complete"
    
    # Give service a moment to start
    log_info "Waiting for service to start..."
    sleep 5
    
    # Hook 3: healthcheck.sh
    log_info "Running healthcheck..."
    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        root@$vm_ip "cd /tmp/app-deployment && chmod +x healthcheck.sh && ./healthcheck.sh" > "$STATE_DIR/hook-healthcheck.log" 2>&1; then
        log_warning "Health check had issues. Check: $STATE_DIR/hook-healthcheck.log"
        cat "$STATE_DIR/hook-healthcheck.log"
        # Don't fail on healthcheck issues
    else
        log_success "Health check passed"
    fi
    
    return 0
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."
    
    local vm_ip=$(state_get "vm_ip")
    
    if [ -z "$vm_ip" ]; then
        log_error "No VM IP found"
        return 1
    fi
    
    # Check if VM is accessible
    log_info "Checking VM accessibility..."
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        -o ConnectTimeout=10 root@$vm_ip "echo 'VM is accessible'" > /dev/null 2>&1; then
        log_success "VM is accessible via SSH"
    else
        log_warning "VM is not yet accessible via SSH"
        return 1
    fi
    
    # Check if app service exists
    log_info "Checking application service..."
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        root@$vm_ip "systemctl list-units --type=service | grep -q $APP_NAME" 2>/dev/null; then
        log_success "Application service found"
    else
        log_warning "Application service not found"
    fi
    
    log_success "Deployment verified"
    return 0
}

# Destroy deployment
destroy_deployment() {
    log_step "Destroying deployment..."
    
    if ! deployment_exists; then
        log_error "No deployment found to destroy"
        log_info "State directory not found: $STATE_DIR"
        return 1
    fi
    
    # Tear down WireGuard interface if it exists
    local wg_interface="wg-${APP_NAME}"
    if sudo wg show "$wg_interface" &>/dev/null; then
        log_info "Tearing down WireGuard interface..."
        sudo wg-quick down "$wg_interface" 2>/dev/null || true
        sudo rm -f "/etc/wireguard/${wg_interface}.conf"
        log_success "WireGuard interface removed"
    fi
    
    # Run Terraform destroy
    if [ -d "$STATE_DIR/terraform" ]; then
        log_info "Destroying infrastructure..."
        echo ""

        # Detect OpenTofu or Terraform (prefer OpenTofu as it's open source)
        if command -v tofu &> /dev/null; then
            TF_CMD="tofu"
        elif command -v terraform &> /dev/null; then
            TF_CMD="terraform"
        else
            log_error "Neither OpenTofu nor Terraform found"
            return 1
        fi

        local orig_dir="$(pwd)"
        cd "$STATE_DIR/terraform" || return 1

        # Update lock file to match current configuration
        log_info "Updating lock file..."
        if ! $TF_CMD init -upgrade -input=false 2>&1 | tee "$STATE_DIR/terraform-init-upgrade.log"; then
            log_warning "Init -upgrade failed, but continuing with destroy..."
        fi

        # Destroy using state file (no variables needed, uses existing state)
        if $TF_CMD destroy -auto-approve -input=false 2>&1 | tee "$STATE_DIR/terraform-destroy.log"; then
            log_success "Infrastructure destroyed"
        else
            log_error "Destroy failed. Check: $STATE_DIR/terraform-destroy.log"
            cd "$orig_dir"
            return 1
        fi

        cd "$orig_dir"
    fi
    
    # Clear state
    state_clear
    
    log_success "Deployment destroyed"
    return 0
}

# Export functions
export -f cleanup_on_error
export -f deploy_app
export -f generate_terraform_config
export -f deploy_app_source
export -f run_app_hooks
export -f verify_deployment
export -f destroy_deployment
