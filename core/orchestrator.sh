#!/usr/bin/env bash
# Orchestrator - Main deployment logic that coordinates everything

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/deployment-status.sh"
source "$SCRIPT_DIR/deployment-id.sh"
source "$SCRIPT_DIR/pattern-loader.sh"
source "$SCRIPT_DIR/app-loader.sh"
source "$SCRIPT_DIR/node-selector.sh"
source "$SCRIPT_DIR/interactive-config.sh"

# Get VM IP from deployment state
get_vm_ip_from_state() {
    # Try to get VM IP from various state files
    if [ -f "$STATE_DIR/state.yaml" ]; then
        # Check different possible IP field names
        local vm_ip=$(grep "^vm_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')
        if [ -n "$vm_ip" ]; then
            echo "$vm_ip"
            return 0
        fi
        
        # Try gateway_ip as fallback
        vm_ip=$(grep "^gateway_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')
        if [ -n "$vm_ip" ]; then
            echo "$vm_ip"
            return 0
        fi
    fi
    
    # Return empty if not found
    echo ""
    return 1
}

# Cleanup on deployment error
cleanup_on_error() {
    local app_name="$1"
    local error_message="${2:-Deployment failed}"
    
    log_warning "Deployment failed: $error_message"
    
    # Mark deployment as failed
    mark_deployment_failed "$app_name" "$error_message"
    
    # Unregister from Docker-style ID system if we had an ID
    if [ -n "${DEPLOYMENT_ID:-}" ] && [ "${DEPLOYMENT_ID:-}" != "false" ]; then
        unregister_deployment "$app_name" || true
    fi
    
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
    
    # Generate unique deployment ID (Docker-style)
    if [ -z "${DEPLOYMENT_ID:-}" ]; then
        export DEPLOYMENT_ID=$(generate_deployment_id)
        log_info "Generated deployment ID: $DEPLOYMENT_ID"
    fi
    
    # Mark deployment as deploying
    mark_deployment_deploying "$APP_NAME"
    
    # Setup error trap
    trap 'cleanup_on_error "$APP_NAME" "$ERROR_MESSAGE"' ERR
    
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
    
    # Ensure dedicated state directory exists (creates per-deployment isolation)
    if [ -z "${DEPLOYMENT_ID:-}" ]; then
        export DEPLOYMENT_ID=$(generate_deployment_id)
        log_info "Generated deployment ID: $DEPLOYMENT_ID"
    fi
    
    # Create dedicated state directory for this deployment
    local dedicated_state_dir="$STATE_BASE_DIR/$DEPLOYMENT_ID"
    mkdir -p "$dedicated_state_dir"
    
    # Update STATE_DIR to point to dedicated directory
    export STATE_DIR="$dedicated_state_dir"
    log_info "Using dedicated state directory: $STATE_DIR"
    
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
            DEPLOY_NODE=$(select_best_node "$DEPLOY_CPU" "$DEPLOY_MEM" "$DEPLOY_DISK" "$DEPLOY_NETWORK" "$CUSTOM_WHITELIST_NODES" "$CUSTOM_BLACKLIST_NODES" "$CUSTOM_BLACKLIST_FARMS" "$CUSTOM_WHITELIST_FARMS" "$CUSTOM_MAX_CPU_USAGE" "$CUSTOM_MAX_DISK_USAGE" "$CUSTOM_MIN_UPTIME_DAYS")
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
            log_success "Selected node: $DEPLOY_NODE"
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
deploy_node: $DEPLOY_NODE
deploy_cpu: $DEPLOY_CPU
deploy_mem: $DEPLOY_MEM
deploy_disk: $DEPLOY_DISK
deploy_network: $DEPLOY_NETWORK
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

    # Step 2.4: Capture real IP addresses from terraform outputs
    log_step "Capturing deployment IP addresses..."
    if [ -d "$STATE_DIR/terraform" ] && [ -f "$STATE_DIR/terraform/terraform.tfstate" ]; then
        cd "$STATE_DIR/terraform" || return 1

        # Capture primary (WireGuard) IP and write as vm_ip
        local real_primary_ip=""
        real_primary_ip=$(terraform output -raw primary_ip 2>/dev/null || echo "")

        if [ -n "$real_primary_ip" ] && [ "$real_primary_ip" != "null" ]; then
            # Write vm_ip to state.yaml
            echo "vm_ip: $real_primary_ip" >> "$STATE_DIR/state.yaml"
            log_success "Captured WireGuard IP: $real_primary_ip"
        else
            log_warning "Could not extract WireGuard IP from terraform output"
        fi

        # Capture Mycelium IPv6 and write as mycelium_ip
        local real_mycelium_ip=""
        real_mycelium_ip=$(terraform output -raw mycelium_ip 2>/dev/null || echo "")

        if [ -n "$real_mycelium_ip" ] && [ "$real_mycelium_ip" != "null" ] && [ "$real_mycelium_ip" != "<nil>" ]; then
            # Write mycelium_ip to state.yaml
            echo "mycelium_ip: $real_mycelium_ip" >> "$STATE_DIR/state.yaml"
            log_success "Captured Mycelium IPv6: $real_mycelium_ip"
        else
            log_debug "Mycelium IP not available (normal if mycelium not enabled)"
        fi

        cd - >/dev/null
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
    
    # Register deployment in Docker-style ID system with contract linkage
    local vm_ip=$(get_vm_ip_from_state)
    
    # Extract node IDs from terraform outputs for contract mapping
    local node_ids=""
    if [ -f "$STATE_DIR/terraform/terraform.tfstate" ]; then
        node_ids=$(cd "$STATE_DIR" && terraform output node_ids 2>/dev/null | jq -r '.[]' 2>/dev/null | tr '\n' ',' | sed 's/,$//' || echo "")
    fi
    
    # Extract contract ID from terraform state (grid_deployment resource ID)
    local contract_id=""
    if [ -f "$STATE_DIR/terraform/terraform.tfstate" ]; then
        # Extract directly from terraform state JSON
        # The grid_deployment resource ID IS the contract ID
        contract_id=$(jq -r '.resources[]? | select(.type == "grid_deployment" and .name == "vm") | .instances[0].attributes.id' "$STATE_DIR/terraform/terraform.tfstate" 2>/dev/null || echo "")
        
        if [ -n "$contract_id" ] && [ "$contract_id" != "null" ]; then
            log_info "Contract ID extracted from terraform state: $contract_id"
        else
            log_warning "Could not extract contract ID from terraform state"
            contract_id=""
        fi
    fi
    
    # Use dedicated state directory for perfect deployment isolation
    local dedicated_state_dir="$STATE_BASE_DIR/$DEPLOYMENT_ID"
    register_deployment "$DEPLOYMENT_ID" "$APP_NAME" "$dedicated_state_dir" "$vm_ip" "$contract_id"
    
    # Mark deployment as active
    mark_deployment_active "$APP_NAME"
    
    # Perform health check to verify deployment
    log_info "Performing health check..."
    if ! perform_deployment_health_check "$APP_NAME" "$PATTERN_NAME"; then
        log_warning "Health check failed - deployment may not be fully functional"
        mark_deployment_failed "$APP_NAME" "Health check failed after deployment"
    fi
    
    log_info "App: $APP_NAME v$APP_VERSION"
    log_info "Pattern: $PATTERN_NAME v$PATTERN_VERSION"
    echo ""

    # Display deployment URLs if available
    display_deployment_urls || true

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

    # Use network-aware IP resolution that respects global preferences
    local DEPLOYMENT_ID=$(basename "$STATE_DIR")
    local vm_ip=$(get_deployment_ip "$DEPLOYMENT_ID")

    if [ -z "$vm_ip" ]; then
        log_error "No VM IP found for preferred network"
        return 1
    fi

    log_info "Preparing VM for app deployment..."
    # Create directories on VM
    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        root@$vm_ip "mkdir -p /tmp/app-deployment /tmp/app-source" 2>/dev/null; then
        log_error "Failed to create deployment directories on VM"
        return 1
    fi

    # Format IP for SCP (IPv6 addresses need brackets for SCP, unlike SSH)
    local scp_host="$vm_ip"
    if [[ "$vm_ip" == *":"* ]]; then
        # IPv6 address - add brackets for SCP
        scp_host="[$vm_ip]"
    fi

    # Copy app deployment hooks to VM (all files, not just .sh)
    log_info "Copying deployment hooks..."
    if ! scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        "$APP_DEPLOYMENT_DIR"/* "root@$scp_host:/tmp/app-deployment/" 2>/dev/null; then
        log_error "Failed to copy deployment hooks to VM ($scp_host)"
        return 1
    fi
    log_success "Deployment hooks copied to VM"

    # Copy app source directory contents if it exists (for scripts, templates, etc.)
    if [ -d "$APP_DIR/src" ]; then
        log_info "Copying app source files..."
        if ! scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "$APP_DIR"/src/* "root@$scp_host:/tmp/app-source/" 2>/dev/null; then
            log_error "Failed to copy app source files to VM ($scp_host)"
            return 1
        fi
        log_success "App source files copied to VM"
    else
        log_info "No app source directory to copy"
    fi

    return 0
}

# Run app deployment hooks
run_app_hooks() {
    log_step "Running application deployment hooks..."

    # Use network-aware IP resolution that respects global preferences
    local DEPLOYMENT_ID=$(basename "$STATE_DIR")
    local vm_ip=$(get_deployment_ip "$DEPLOYMENT_ID")

    if [ -z "$vm_ip" ]; then
        log_error "No VM IP found for preferred network"
        return 1
    fi
    
    # Load credentials to get git config
    if [ -f "$CREDENTIALS_FILE" ]; then
        source "$DEPLOYER_ROOT/core/login.sh"
        load_credentials || true
    fi
    
    # Prepare environment variables for deployment hooks
    local env_vars=""
    if [ -n "$TFGRID_GIT_NAME" ]; then
        env_vars="export TFGRID_GIT_NAME='$TFGRID_GIT_NAME';"
        log_info "Passing git name to deployment: $TFGRID_GIT_NAME"
    fi
    if [ -n "$TFGRID_GIT_EMAIL" ]; then
        env_vars="$env_vars export TFGRID_GIT_EMAIL='$TFGRID_GIT_EMAIL';"
        log_info "Passing git email to deployment: $TFGRID_GIT_EMAIL"
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

    # Add verbose flag support
    local verbose_flag=""
    if [ "${TFGRID_VERBOSE:-}" = "1" ] || [ "${VERBOSE:-}" = "1" ]; then
        verbose_flag="-v"
        log_info "Verbose mode enabled - hook output will be shown in real-time"
    fi
    
    # Hook 1: setup.sh
    log_info "Running setup hook..."
    if [ "${TFGRID_VERBOSE:-}" = "1" ] || [ "${VERBOSE:-}" = "1" ]; then
        # Verbose mode: Show output in real-time
        if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "cd /tmp/app-deployment && chmod +x setup.sh && $env_vars ./setup.sh" 2>&1 | tee "$STATE_DIR/hook-setup.log"; then
            log_error "Setup hook failed. Check: $STATE_DIR/hook-setup.log"
            return 1
        fi
    else
        # Normal mode: Buffer output to log file only
        if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "cd /tmp/app-deployment && chmod +x setup.sh && $env_vars ./setup.sh" > "$STATE_DIR/hook-setup.log" 2>&1; then
            log_error "Setup hook failed. Check: $STATE_DIR/hook-setup.log"
            cat "$STATE_DIR/hook-setup.log"
            return 1
        fi
    fi
    log_success "Setup complete"
    
    # Hook 2: configure.sh
    log_info "Running configure hook..."

    # Check if configure hook is optional for this app
    local configure_optional=$(yaml_get "$APP_MANIFEST" "hook_config.configure.optional" 2>/dev/null || echo "false")

    if [ "${TFGRID_VERBOSE:-}" = "1" ] || [ "${VERBOSE:-}" = "1" ]; then
        # Verbose mode: Show output in real-time
        if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "cd /tmp/app-deployment && chmod +x configure.sh && $env_vars ./configure.sh" 2>&1 | tee "$STATE_DIR/hook-configure.log"; then
            if [ "$configure_optional" = "true" ]; then
                log_warning "Configure hook failed (optional). Check: $STATE_DIR/hook-configure.log"
            else
                log_error "Configure hook failed. Check: $STATE_DIR/hook-configure.log"
                return 1
            fi
        fi
    else
        # Normal mode: Buffer output to log file only
        if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "cd /tmp/app-deployment && chmod +x configure.sh && $env_vars ./configure.sh" > "$STATE_DIR/hook-configure.log" 2>&1; then
            if [ "$configure_optional" = "true" ]; then
                log_warning "Configure hook failed (optional). Check: $STATE_DIR/hook-configure.log"
            else
                log_error "Configure hook failed. Check: $STATE_DIR/hook-configure.log"
                cat "$STATE_DIR/hook-configure.log"
                return 1
            fi
        fi
    fi

    if [ "$configure_optional" = "true" ]; then
        log_success "Configuration complete (optional hook)"
    else
        log_success "Configuration complete"
    fi
    
    # Give service a moment to start
    log_info "Waiting for service to start..."
    sleep 5
    
    # Hook 3: healthcheck.sh
    log_info "Running healthcheck..."
    if [ "${TFGRID_VERBOSE:-}" = "1" ] || [ "${VERBOSE:-}" = "1" ]; then
        # Verbose mode: Show output in real-time
        if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "cd /tmp/app-deployment && chmod +x healthcheck.sh && ./healthcheck.sh" 2>&1 | tee "$STATE_DIR/hook-healthcheck.log"; then
            log_warning "Health check had issues. Check: $STATE_DIR/hook-healthcheck.log"
            # Don't fail on healthcheck issues
        else
            log_success "Health check passed"
        fi
    else
        # Normal mode: Buffer output to log file only
        if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "cd /tmp/app-deployment && chmod +x healthcheck.sh && ./healthcheck.sh" > "$STATE_DIR/hook-healthcheck.log" 2>&1; then
            log_warning "Health check had issues. Check: $STATE_DIR/hook-healthcheck.log"
            cat "$STATE_DIR/hook-healthcheck.log"
            # Don't fail on healthcheck issues
        else
            log_success "Health check passed"
        fi
    fi
    
    return 0
}

# Verify deployment
verify_deployment() {
    log_step "Verifying deployment..."

    # Use network-aware IP resolution that respects global preferences
    local DEPLOYMENT_ID=$(basename "$STATE_DIR")
    local vm_ip=$(get_deployment_ip "$DEPLOYMENT_ID")

    if [ -z "$vm_ip" ]; then
        log_error "No VM IP found for preferred network"
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
    
    # Load deployment variables from state for Terraform destroy
    if [ -f "$STATE_DIR/state.yaml" ]; then
        log_info "Loading deployment configuration..."
        local pattern_name=$(yaml_get "$STATE_DIR/state.yaml" "pattern_name")
        local deploy_node=$(yaml_get "$STATE_DIR/state.yaml" "deploy_node")
        local deploy_cpu=$(yaml_get "$STATE_DIR/state.yaml" "deploy_cpu")
        local deploy_mem=$(yaml_get "$STATE_DIR/state.yaml" "deploy_mem")
        local deploy_disk=$(yaml_get "$STATE_DIR/state.yaml" "deploy_disk")
        local deploy_network=$(yaml_get "$STATE_DIR/state.yaml" "deploy_network")
        
        # Export network variable
        export TF_VAR_tfgrid_network="${deploy_network:-main}"
        
        # Export pattern-specific variables
        case "$pattern_name" in
            single-vm)
                export TF_VAR_vm_node=$deploy_node
                export TF_VAR_vm_cpu=$deploy_cpu
                export TF_VAR_vm_mem=$deploy_mem
                export TF_VAR_vm_disk=$deploy_disk
                ;;
            gateway)
                export TF_VAR_gateway_node=$deploy_node
                export TF_VAR_gateway_cpu=$deploy_cpu
                export TF_VAR_gateway_mem=$deploy_mem
                export TF_VAR_gateway_disk=$deploy_disk
                ;;
            k3s)
                export TF_VAR_management_node=$deploy_node
                export TF_VAR_management_cpu=$deploy_cpu
                export TF_VAR_management_mem=$deploy_mem
                export TF_VAR_management_disk=$deploy_disk
                ;;
            *)
                # Fallback for unknown patterns
                export TF_VAR_vm_node=$deploy_node
                export TF_VAR_vm_cpu=$deploy_cpu
                export TF_VAR_vm_mem=$deploy_mem
                export TF_VAR_vm_disk=$deploy_disk
                ;;
        esac
        log_info "Loaded variables: pattern=$pattern_name, node=$deploy_node"
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
    
    # Unregister from Docker-style ID system
    unregister_deployment "$APP_NAME"
    
    log_success "Deployment destroyed"
    return 0
}

# Display deployment URLs after successful deployment
display_deployment_urls() {
    # Get deployment information from state file
    local primary_ip=$(state_get "vm_ip") # WireGuard IP stored as vm_ip
    local primary_ip_type="wireguard"    # Always WireGuard for now
    local mycelium_ip=$(state_get "mycelium_ip")

    # Check if app has custom launch command
    local launch_cmd=$(yaml_get "$APP_MANIFEST" "commands.launch.script" 2>/dev/null)

    if [ -n "$launch_cmd" ]; then
        log_info "🌐 Access your application:"
        echo "  • Launch in browser: tfgrid-compose launch $APP_NAME"
        return 0
    fi

    # Default URL display for common patterns
    case "$APP_NAME" in
        tfgrid-ai-stack)
            log_info "🌐 Access your services:"
            if [ "$primary_ip_type" = "wireguard" ] && [ -n "$primary_ip" ]; then
                echo "  • Gitea (Git hosting): http://$primary_ip/git/"
                echo "  • AI Agent API: http://$primary_ip/api/"
            fi
            if [ -n "$mycelium_ip" ]; then
                echo "  • Gitea (Mycelium): http://[$mycelium_ip]/git/"
                echo "  • AI Agent API (Mycelium): http://[$mycelium_ip]/api/"
            fi
            echo "  • Launch in browser: tfgrid-compose launch $APP_NAME"
            ;;
        tfgrid-gitea)
            log_info "🌐 Access Gitea:"
            if [ "$primary_ip_type" = "wireguard" ] && [ -n "$primary_ip" ]; then
                echo "  • Web interface: http://$primary_ip:3000/"
            fi
            if [ -n "$mycelium_ip" ]; then
                echo "  • Web interface (Mycelium): http://[$mycelium_ip]:3000/"
            fi
            echo "  • Launch in browser: tfgrid-compose launch $APP_NAME"
            ;;
        tfgrid-ai-agent)
            log_info "🌐 AI Agent deployed:"
            if [ "$primary_ip_type" = "wireguard" ] && [ -n "$primary_ip" ]; then
                echo "  • SSH access: tfgrid-compose ssh $APP_NAME"
            fi
            ;;
        *)
            # Generic display for other apps
            if [ "$primary_ip_type" = "wireguard" ] && [ -n "$primary_ip" ]; then
                log_info "🌐 Deployment accessible at: $primary_ip"
            fi
            if [ -n "$mycelium_ip" ]; then
                log_info "🌐 Mycelium access: [$mycelium_ip]"
            fi
            ;;
    esac
}

# Export functions
export -f cleanup_on_error
export -f deploy_app
export -f generate_terraform_config
export -f deploy_app_source
export -f run_app_hooks
export -f verify_deployment
export -f destroy_deployment
export -f display_deployment_urls
