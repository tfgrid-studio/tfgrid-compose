#!/usr/bin/env bash
# Orchestrator - Main deployment logic that coordinates everything

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Generate K3s multi-node inventory from terraform state
generate_k3s_inventory() {
    local state_dir="$1"
    local output_dir="$2"
    local tf_dir="$state_dir/terraform"
    local output_file="$output_dir/inventory.ini"
    
    # Get terraform outputs
    local terraform_output
    terraform_output=$(tofu -chdir="$tf_dir" show -json 2>/dev/null)
    
    if [ -z "$terraform_output" ]; then
        log_error "Failed to get terraform outputs"
        return 1
    fi
    
    # Extract node information
    local management_wireguard_ip=$(echo "$terraform_output" | jq -r '.values.outputs.management_node_wireguard_ip.value // empty')
    local management_mycelium_ip=$(echo "$terraform_output" | jq -r '.values.outputs.management_mycelium_ip.value // empty')
    local wireguard_ips=$(echo "$terraform_output" | jq -r '.values.outputs.wireguard_ips.value // {}')
    local mycelium_ips=$(echo "$terraform_output" | jq -r '.values.outputs.mycelium_ips.value // {}')
    
    # Extract ingress node information
    local ingress_wireguard_ips=$(echo "$terraform_output" | jq -r '.values.outputs.ingress_wireguard_ips.value // {}')
    local ingress_mycelium_ips=$(echo "$terraform_output" | jq -r '.values.outputs.ingress_mycelium_ips.value // {}')
    local ingress_public_ips=$(echo "$terraform_output" | jq -r '.values.outputs.ingress_public_ips.value // {}')
    local has_ingress_nodes=$(echo "$terraform_output" | jq -r '.values.outputs.has_ingress_nodes.value // false')
    
    # Get network preference from .env or default to wireguard
    local main_network="${MAIN_NETWORK:-wireguard}"
    local management_ip node_ips ingress_node_ips
    
    case "$main_network" in
        "mycelium")
            management_ip="$management_mycelium_ip"
            node_ips="$mycelium_ips"
            ingress_node_ips="$ingress_mycelium_ips"
            log_info "Using Mycelium IPs for K3s inventory"
            ;;
        *)
            management_ip="$management_wireguard_ip"
            node_ips="$wireguard_ips"
            ingress_node_ips="$ingress_wireguard_ips"
            log_info "Using WireGuard IPs for K3s inventory"
            ;;
    esac
    
    if [ -z "$management_ip" ]; then
        log_error "Failed to extract management node IP"
        return 1
    fi
    
    # Count nodes from terraform output
    local control_count=$(echo "$node_ips" | jq -r 'keys | length')
    local ingress_count=$(echo "$ingress_node_ips" | jq -r 'keys | length' 2>/dev/null || echo "0")
    
    # Get control/worker split from .env
    local k3s_control_nodes="${K3S_CONTROL_NODES:-3}"
    local k3s_worker_nodes="${K3S_WORKER_NODES:-3}"
    
    # Generate inventory file
    cat > "$output_file" << EOF
# TFGrid K3s Cluster Ansible Inventory
# Generated on $(date)
# Network: ${main_network}

# Management Node
[k3s_management]
mgmt_host ansible_host=${management_ip} ansible_user=root ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

# K3s Control Plane Nodes
[k3s_control]
EOF

    # Add control plane nodes
    local idx=0
    echo "$node_ips" | jq -r 'to_entries | sort_by(.key) | .[] | .key + " " + .value' | \
    while read -r key ip; do
        if [ $idx -lt $k3s_control_nodes ]; then
            local node_num=$((idx + 1))
            echo "node${node_num} ansible_host=${ip} ansible_user=root ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'" >> "$output_file"
        fi
        idx=$((idx + 1))
    done

    # Add worker nodes section
    cat >> "$output_file" << EOF

# K3s Worker Nodes
[k3s_worker]
EOF

    # Add worker nodes
    idx=0
    echo "$node_ips" | jq -r 'to_entries | sort_by(.key) | .[] | .key + " " + .value' | \
    while read -r key ip; do
        if [ $idx -ge $k3s_control_nodes ]; then
            local node_num=$((idx + 1))
            echo "node${node_num} ansible_host=${ip} ansible_user=root ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'" >> "$output_file"
        fi
        idx=$((idx + 1))
    done

    # Add ingress nodes if present
    if [ "$has_ingress_nodes" = "true" ] && [ "$ingress_count" -gt 0 ]; then
        cat >> "$output_file" << EOF

# K3s Ingress Nodes (dedicated, with public IPs)
[k3s_ingress]
EOF
        local ingress_idx=0
        echo "$ingress_node_ips" | jq -r 'to_entries | sort_by(.key) | .[] | .key + " " + .value' 2>/dev/null | \
        while read -r key ip; do
            if [ -n "$ip" ]; then
                local ingress_num=$((ingress_idx + 1))
                local public_ip=$(echo "$ingress_public_ips" | jq -r ".\"$key\" // empty")
                echo "ingress${ingress_num} ansible_host=${ip} ansible_user=root public_ip=${public_ip} ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'" >> "$output_file"
                ingress_idx=$((ingress_idx + 1))
            fi
        done
    fi

    # Add cluster groups and variables
    if [ "$has_ingress_nodes" = "true" ] && [ "$ingress_count" -gt 0 ]; then
        cat >> "$output_file" << EOF

# All K3s Nodes
[k3s_cluster:children]
k3s_management
k3s_control
k3s_worker
k3s_ingress

# Global Variables
[all:vars]
ansible_python_interpreter=/usr/bin/python3
k3s_version=v1.32.3+k3s1
primary_control_node=node1
has_ingress_nodes=true
EOF
    else
        cat >> "$output_file" << EOF

# All K3s Nodes
[k3s_cluster:children]
k3s_management
k3s_control
k3s_worker

# Global Variables
[all:vars]
ansible_python_interpreter=/usr/bin/python3
k3s_version=v1.32.3+k3s1
primary_control_node=node1
has_ingress_nodes=false
EOF
    fi

    # Add primary control IP
    local first_control_ip=$(echo "$node_ips" | jq -r 'to_entries | sort_by(.key) | .[0].value // empty')
    if [ -n "$first_control_ip" ]; then
        echo "primary_control_ip=${first_control_ip}" >> "$output_file"
    fi

    log_success "K3s inventory generated with $(echo "$node_ips" | jq 'keys | length') cluster nodes"
    return 0
}

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
        # Check different possible IP field names (take first match only)
        local vm_ip=$(grep "^vm_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | head -n1 | awk '{print $2}')
        if [ -n "$vm_ip" ]; then
            echo "$vm_ip"
            return 0
        fi
        
        # Try gateway_ip as fallback
        vm_ip=$(grep "^gateway_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | head -n1 | awk '{print $2}')
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

    # Prefer deployment ID for all tracking if available
    local deployment_identifier="${DEPLOYMENT_ID:-$app_name}"

    log_warning "Deployment failed: $error_message"

    # Mark deployment as failed using deployment ID when possible
    mark_deployment_failed "$deployment_identifier" "$error_message"

    # Unregister from Docker-style ID system if we had an ID
    if [ -n "${DEPLOYMENT_ID:-}" ] && [ "${DEPLOYMENT_ID:-}" != "false" ]; then
        unregister_deployment "$DEPLOYMENT_ID" || true
    fi
    
    # Don't clean if user wants to debug
    if [ "${TFGRID_DEBUG:-}" = "1" ]; then
        log_info "Debug mode: Keeping state for inspection"
        return 0
    fi
    
    # Clean stale state to allow retry (state directory is keyed by deployment ID)
    clean_stale_state "$deployment_identifier"
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
    
    # Mark deployment as deploying (track by deployment ID)
    mark_deployment_deploying "$DEPLOYMENT_ID"
    
    # Setup error trap
    trap 'cleanup_on_error "$DEPLOYMENT_ID" "$ERROR_MESSAGE"' ERR
    
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
    # For AI-stack style apps, use resources.cpu.*, for single-vm style apps
    # prefer resources.vm.* when present.
    MANIFEST_CPU=$(yaml_get "$APP_MANIFEST" "resources.cpu.recommended" || yaml_get "$APP_MANIFEST" "resources.cpu.min" || echo "2")
    MANIFEST_MEM=$(yaml_get "$APP_MANIFEST" "resources.memory.recommended" || yaml_get "$APP_MANIFEST" "resources.memory.min" || echo "4096")
    MANIFEST_DISK=$(yaml_get "$APP_MANIFEST" "resources.disk.recommended" || yaml_get "$APP_MANIFEST" "resources.disk.min" || echo "50")

    # Read manifest minimums (used for size profiles and validation)
    local MIN_CPU MIN_MEM MIN_DISK MANIFEST_IPV4 DEPLOY_IPV4
    MIN_CPU=$(yaml_get "$APP_MANIFEST" "resources.cpu.min" 2>/dev/null || echo "")
    MIN_MEM=$(yaml_get "$APP_MANIFEST" "resources.memory.min" 2>/dev/null || echo "")
    MIN_DISK=$(yaml_get "$APP_MANIFEST" "resources.disk.min" 2>/dev/null || echo "")

    [ "$MIN_CPU" = "null" ] && MIN_CPU=""
    [ "$MIN_MEM" = "null" ] && MIN_MEM=""
    [ "$MIN_DISK" = "null" ] && MIN_DISK=""

    [ -z "$MIN_CPU" ] && MIN_CPU="$MANIFEST_CPU"
    [ -z "$MIN_MEM" ] && MIN_MEM="$MANIFEST_MEM"
    [ -z "$MIN_DISK" ] && MIN_DISK="$MANIFEST_DISK"

    # Determine default public IPv4 behavior from manifest (network.public_ipv4)
    MANIFEST_IPV4=$(yaml_get "$APP_MANIFEST" "network.public_ipv4" 2>/dev/null || echo "")
    [ "$MANIFEST_IPV4" = "null" ] && MANIFEST_IPV4=""
    case "$MANIFEST_IPV4" in
        true|True|TRUE|yes|on|1)
            MANIFEST_IPV4="true"
            ;;
        false|False|FALSE|no|off|0)
            MANIFEST_IPV4="false"
            ;;
        *)
            MANIFEST_IPV4=""
            ;;
    esac

    # Apply size profiles when requested (dev/small/medium/large/xlarge)
    if [ -n "${CUSTOM_SIZE:-}" ]; then
        local size_lc
        size_lc=$(echo "$CUSTOM_SIZE" | tr '[:upper:]' '[:lower:]')
        case "$size_lc" in
            dev)
                MANIFEST_CPU="$MIN_CPU"
                MANIFEST_MEM="$MIN_MEM"
                MANIFEST_DISK="$MIN_DISK"
                ;;
            small)
                # Use recommended values (already MANIFEST_*)
                ;;
            medium)
                MANIFEST_CPU=$((MANIFEST_CPU * 2))
                MANIFEST_MEM=$((MANIFEST_MEM * 2))
                MANIFEST_DISK=$((MANIFEST_DISK * 2))
                ;;
            large)
                MANIFEST_CPU=$((MANIFEST_CPU * 4))
                MANIFEST_MEM=$((MANIFEST_MEM * 4))
                MANIFEST_DISK=$((MANIFEST_DISK * 4))
                ;;
            xlarge)
                MANIFEST_CPU=$((MANIFEST_CPU * 8))
                MANIFEST_MEM=$((MANIFEST_MEM * 8))
                MANIFEST_DISK=$((MANIFEST_DISK * 8))
                ;;
            *)
                log_warning "Unknown size profile: $CUSTOM_SIZE (expected: dev/small/medium/large/xlarge)"
                ;;
        esac
    fi

    # Normalize CLI overrides for memory/disk (accept 8G, 8192M, 200G, etc.)
    if [ -n "${CUSTOM_MEM:-}" ]; then
        local parsed_mem
        parsed_mem=$(parse_memory_to_mb "$CUSTOM_MEM") || return 1
        CUSTOM_MEM="$parsed_mem"
    fi

    if [ -n "${CUSTOM_DISK:-}" ]; then
        local parsed_disk
        parsed_disk=$(parse_disk_to_gb "$CUSTOM_DISK") || return 1
        CUSTOM_DISK="$parsed_disk"
    fi

    # Disk type (e.g. ssd/hdd) can be passed from CLI or env and forwarded to Terraform
    local DEPLOY_DISK_TYPE=""
    if [ -n "${CUSTOM_DISK_TYPE:-}" ]; then
        DEPLOY_DISK_TYPE="$CUSTOM_DISK_TYPE"
    elif [ -n "${TF_VAR_vm_disk_type:-}" ]; then
        DEPLOY_DISK_TYPE="$TF_VAR_vm_disk_type"
    fi

    # Determine IPv4 behavior (default from manifest, override via CLI)
    if [ -n "${CUSTOM_IPV4:-}" ]; then
        case "$CUSTOM_IPV4" in
            true|false)
                DEPLOY_IPV4="$CUSTOM_IPV4"
                ;;
            *)
                log_warning "Invalid value for --ipv4: $CUSTOM_IPV4 (expected true|false). Using 'true'."
                DEPLOY_IPV4="true"
                ;;
        esac
    else
        DEPLOY_IPV4="$MANIFEST_IPV4"
    fi

    [ -z "$DEPLOY_IPV4" ] && DEPLOY_IPV4="false"

    if [ "$DEPLOY_IPV4" = "true" ]; then
        export CUSTOM_REQUIRE_PUBLIC_IPV4="true"
    fi

    if [ "$PATTERN_NAME" = "single-vm" ]; then
        # Override manifest resources from single-vm specific config when available
        local vm_cpu vm_mem vm_disk
        vm_cpu=$(yaml_get "$APP_MANIFEST" "resources.vm.cpu" 2>/dev/null || echo "")
        vm_mem=$(yaml_get "$APP_MANIFEST" "resources.vm.memory" 2>/dev/null || echo "")
        vm_disk=$(yaml_get "$APP_MANIFEST" "resources.vm.disk" 2>/dev/null || echo "")

        [ "$vm_cpu" = "null" ] && vm_cpu=""
        [ "$vm_mem" = "null" ] && vm_mem=""
        [ "$vm_disk" = "null" ] && vm_disk=""

        [ -n "$vm_cpu" ] && MANIFEST_CPU="$vm_cpu"
        [ -n "$vm_mem" ] && MANIFEST_MEM="$vm_mem"
        [ -n "$vm_disk" ] && MANIFEST_DISK="$vm_disk"

        DEPLOY_CPU=${CUSTOM_CPU:-$MANIFEST_CPU}
        DEPLOY_MEM=${CUSTOM_MEM:-$MANIFEST_MEM}
        DEPLOY_DISK=${CUSTOM_DISK:-$MANIFEST_DISK}
    else
        DEPLOY_CPU=${CUSTOM_CPU:-${TF_VAR_ai_agent_cpu:-$MANIFEST_CPU}}
        DEPLOY_MEM=${CUSTOM_MEM:-${TF_VAR_ai_agent_mem:-$MANIFEST_MEM}}
        DEPLOY_DISK=${CUSTOM_DISK:-${TF_VAR_ai_agent_disk:-$MANIFEST_DISK}}
    fi

    # Enforce manifest minimums to prevent under-provisioning (skip for multi-node patterns like k3s)
    if [ "$PATTERN_NAME" != "k3s" ]; then
        if [ -n "$MIN_CPU" ] && [ -n "$DEPLOY_CPU" ] && [ "$DEPLOY_CPU" != "null" ] && [ "$DEPLOY_CPU" -lt "$MIN_CPU" ] 2>/dev/null; then
            log_error "Requested CPU ($DEPLOY_CPU) below app minimum ($MIN_CPU)"
            return 1
        fi
        if [ -n "$MIN_MEM" ] && [ -n "$DEPLOY_MEM" ] && [ "$DEPLOY_MEM" != "null" ] && [ "$DEPLOY_MEM" -lt "$MIN_MEM" ] 2>/dev/null; then
            log_error "Requested memory (${DEPLOY_MEM}MB) below app minimum (${MIN_MEM}MB)"
            return 1
        fi
        if [ -n "$MIN_DISK" ] && [ -n "$DEPLOY_DISK" ] && [ "$DEPLOY_DISK" != "null" ] && [ "$DEPLOY_DISK" -lt "$MIN_DISK" ] 2>/dev/null; then
            log_error "Requested disk (${DEPLOY_DISK}GB) below app minimum (${MIN_DISK}GB)"
            return 1
        fi
    fi

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
            # K3s pattern handles its own multi-node selection later
            if [ "$PATTERN_NAME" = "k3s" ]; then
                log_info "K3s pattern: Multi-node selection will be performed"
                DEPLOY_NODE="k3s-multi"  # Placeholder, actual selection happens in pattern-specific block
            else
                # Auto-select via GridProxy for single-node patterns
                log_info "Resources: $DEPLOY_CPU CPU, ${DEPLOY_MEM}MB RAM, ${DEPLOY_DISK}GB disk"
                log_info "Auto-selecting best available node..."
                echo ""
                # For automatic selection during deployments, use blacklist/whitelist
                # preferences but do NOT enforce global CPU/disk/uptime thresholds.
                # Those thresholds are still honored by the standalone node browser
                # (tfgrid-compose nodes) via query_gridproxy.
                #
                # select_best_node(cpu, mem_mb, disk_gb, network,
                #   cli_blacklist_nodes, cli_blacklist_farms, cli_whitelist_farms,
                #   cli_max_cpu, cli_max_disk, cli_min_uptime)
                [ -n "$CUSTOM_WHITELIST_FARMS" ] && log_info "Farm filter: $CUSTOM_WHITELIST_FARMS"
                DEPLOY_NODE=$(select_best_node \
                    "$DEPLOY_CPU" \
                    "$DEPLOY_MEM" \
                    "$DEPLOY_DISK" \
                    "$DEPLOY_NETWORK" \
                    "$CUSTOM_BLACKLIST_NODES" \
                    "$CUSTOM_BLACKLIST_FARMS" \
                    "$CUSTOM_WHITELIST_FARMS" \
                    "" \
                    "" \
                    "")
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
            export TF_VAR_vm_public_ipv4=$DEPLOY_IPV4
            if [ -n "$DEPLOY_DISK_TYPE" ]; then
                export TF_VAR_vm_disk_type=$DEPLOY_DISK_TYPE
            fi
            log_info "Exporting single-vm variables: node=$DEPLOY_NODE, cpu=$DEPLOY_CPU, mem=$DEPLOY_MEM, disk=$DEPLOY_DISK"
            ;;
        gateway)
            # Gateway pattern (for now, use single node for gateway)
            export TF_VAR_gateway_node=$DEPLOY_NODE
            export TF_VAR_gateway_cpu=$DEPLOY_CPU
            export TF_VAR_gateway_mem=$DEPLOY_MEM
            export TF_VAR_gateway_disk=$DEPLOY_DISK
            if [ -n "$DEPLOY_DISK_TYPE" ]; then
                export TF_VAR_gateway_disk_type=$DEPLOY_DISK_TYPE
            fi
            # Backend nodes would need additional selection logic
            log_warning "Gateway pattern: Using single node for gateway. Multi-node selection coming in v0.11.0"
            ;;
        k3s)
            # K3s pattern - Multi-node auto-selection
            # Read cluster configuration from app's tfgrid-compose.yaml
            local app_manifest="$APP_MANIFEST"
            
            # Node counts from manifest or environment or defaults
            local K3S_CONTROL_COUNT=${K3S_CONTROL_COUNT:-$(yaml_get "$app_manifest" "nodes.masters.count" 2>/dev/null)}
            local K3S_WORKER_COUNT=${K3S_WORKER_COUNT:-$(yaml_get "$app_manifest" "nodes.workers.count" 2>/dev/null)}
            local K3S_INGRESS_COUNT=${K3S_INGRESS_COUNT:-$(yaml_get "$app_manifest" "nodes.ingress.count" 2>/dev/null)}
            K3S_CONTROL_COUNT=${K3S_CONTROL_COUNT:-3}
            K3S_WORKER_COUNT=${K3S_WORKER_COUNT:-3}
            K3S_INGRESS_COUNT=${K3S_INGRESS_COUNT:-0}
            
            # Resource specs from manifest or environment or defaults
            local K3S_MGMT_CPU=${K3S_MGMT_CPU:-1}
            local K3S_MGMT_MEM=${K3S_MGMT_MEM:-2048}
            local K3S_MGMT_DISK=${K3S_MGMT_DISK:-25}
            local K3S_CONTROL_CPU=${K3S_CONTROL_CPU:-$(yaml_get "$app_manifest" "resources.master.cpu" 2>/dev/null)}
            local K3S_CONTROL_MEM=${K3S_CONTROL_MEM:-$(yaml_get "$app_manifest" "resources.master.memory" 2>/dev/null)}
            local K3S_CONTROL_DISK=${K3S_CONTROL_DISK:-$(yaml_get "$app_manifest" "resources.master.disk" 2>/dev/null)}
            local K3S_WORKER_CPU=${K3S_WORKER_CPU:-$(yaml_get "$app_manifest" "resources.worker.cpu" 2>/dev/null)}
            local K3S_WORKER_MEM=${K3S_WORKER_MEM:-$(yaml_get "$app_manifest" "resources.worker.memory" 2>/dev/null)}
            local K3S_WORKER_DISK=${K3S_WORKER_DISK:-$(yaml_get "$app_manifest" "resources.worker.disk" 2>/dev/null)}
            local K3S_INGRESS_CPU=${K3S_INGRESS_CPU:-$(yaml_get "$app_manifest" "resources.ingress.cpu" 2>/dev/null)}
            local K3S_INGRESS_MEM=${K3S_INGRESS_MEM:-$(yaml_get "$app_manifest" "resources.ingress.memory" 2>/dev/null)}
            local K3S_INGRESS_DISK=${K3S_INGRESS_DISK:-$(yaml_get "$app_manifest" "resources.ingress.disk" 2>/dev/null)}
            # Apply defaults if not set
            K3S_CONTROL_CPU=${K3S_CONTROL_CPU:-4}
            K3S_CONTROL_MEM=${K3S_CONTROL_MEM:-8192}
            K3S_CONTROL_DISK=${K3S_CONTROL_DISK:-50}
            K3S_WORKER_CPU=${K3S_WORKER_CPU:-4}
            K3S_WORKER_MEM=${K3S_WORKER_MEM:-8192}
            K3S_WORKER_DISK=${K3S_WORKER_DISK:-100}
            K3S_INGRESS_CPU=${K3S_INGRESS_CPU:-2}
            K3S_INGRESS_MEM=${K3S_INGRESS_MEM:-4096}
            K3S_INGRESS_DISK=${K3S_INGRESS_DISK:-25}
            
            log_step "K3s cluster node selection"
            local total_nodes=$((1 + K3S_CONTROL_COUNT + K3S_WORKER_COUNT + K3S_INGRESS_COUNT))
            log_info "Cluster: 1 mgmt + $K3S_CONTROL_COUNT control + $K3S_WORKER_COUNT worker + $K3S_INGRESS_COUNT ingress = $total_nodes nodes"
            echo ""
            
            local all_selected=""
            
            # 1. Select management node
            log_info "Selecting management node..."
            local mgmt_node=$(select_best_node "$K3S_MGMT_CPU" "$K3S_MGMT_MEM" "$K3S_MGMT_DISK" "$DEPLOY_NETWORK" \
                "$CUSTOM_BLACKLIST_NODES" "$CUSTOM_BLACKLIST_FARMS" "$CUSTOM_WHITELIST_FARMS" "" "" "")
            mgmt_node=$(echo "$mgmt_node" | tr -d '[:space:]')
            if [ -z "$mgmt_node" ] || [ "$mgmt_node" = "null" ]; then
                log_error "Failed to select management node"
                return 1
            fi
            all_selected="$mgmt_node"
            export TF_VAR_management_node=$mgmt_node
            export TF_VAR_management_cpu=$K3S_MGMT_CPU
            export TF_VAR_management_mem=$K3S_MGMT_MEM
            export TF_VAR_management_disk=$K3S_MGMT_DISK
            
            # 2. Select control plane nodes
            log_info "Selecting $K3S_CONTROL_COUNT control plane nodes..."
            local control_nodes=$(select_multiple_nodes "$K3S_CONTROL_COUNT" "$K3S_CONTROL_CPU" "$K3S_CONTROL_MEM" "$K3S_CONTROL_DISK" \
                "$DEPLOY_NETWORK" "false" "$all_selected" "$CUSTOM_BLACKLIST_FARMS" "$CUSTOM_WHITELIST_FARMS")
            if [ -z "$control_nodes" ]; then
                log_error "Failed to select control plane nodes"
                return 1
            fi
            all_selected="$all_selected,$control_nodes"
            # Convert comma-separated to Terraform list format [1,2,3]
            local control_tf="[$(echo "$control_nodes" | tr ',' ',')]"
            export TF_VAR_control_nodes="$control_tf"
            export TF_VAR_control_cpu=$K3S_CONTROL_CPU
            export TF_VAR_control_mem=$K3S_CONTROL_MEM
            export TF_VAR_control_disk=$K3S_CONTROL_DISK
            
            # 3. Select worker nodes
            log_info "Selecting $K3S_WORKER_COUNT worker nodes..."
            local worker_nodes=$(select_multiple_nodes "$K3S_WORKER_COUNT" "$K3S_WORKER_CPU" "$K3S_WORKER_MEM" "$K3S_WORKER_DISK" \
                "$DEPLOY_NETWORK" "false" "$all_selected" "$CUSTOM_BLACKLIST_FARMS" "$CUSTOM_WHITELIST_FARMS")
            if [ -z "$worker_nodes" ]; then
                log_error "Failed to select worker nodes"
                return 1
            fi
            all_selected="$all_selected,$worker_nodes"
            local worker_tf="[$(echo "$worker_nodes" | tr ',' ',')]"
            export TF_VAR_worker_nodes="$worker_tf"
            export TF_VAR_worker_cpu=$K3S_WORKER_CPU
            export TF_VAR_worker_mem=$K3S_WORKER_MEM
            export TF_VAR_worker_disk=$K3S_WORKER_DISK
            
            # 4. Select ingress nodes (if configured)
            if [ "$K3S_INGRESS_COUNT" -gt 0 ]; then
                log_info "Selecting $K3S_INGRESS_COUNT ingress nodes (with public IPv4)..."
                local ingress_nodes=$(select_multiple_nodes "$K3S_INGRESS_COUNT" "$K3S_INGRESS_CPU" "$K3S_INGRESS_MEM" "$K3S_INGRESS_DISK" \
                    "$DEPLOY_NETWORK" "true" "$all_selected" "$CUSTOM_BLACKLIST_FARMS" "$CUSTOM_WHITELIST_FARMS")
                if [ -z "$ingress_nodes" ]; then
                    log_error "Failed to select ingress nodes (need public IPv4)"
                    return 1
                fi
                local ingress_tf="[$(echo "$ingress_nodes" | tr ',' ',')]"
                export TF_VAR_ingress_nodes="$ingress_tf"
                export TF_VAR_ingress_cpu=$K3S_INGRESS_CPU
                export TF_VAR_ingress_mem=$K3S_INGRESS_MEM
                export TF_VAR_ingress_disk=$K3S_INGRESS_DISK
                export TF_VAR_worker_public_ipv4=false
            else
                export TF_VAR_ingress_nodes="[]"
                export TF_VAR_worker_public_ipv4=true
            fi
            
            log_success "K3s cluster nodes selected successfully"
            echo ""
            ;;
        *)
            # Unknown pattern - export generic variables
            export TF_VAR_vm_node=$DEPLOY_NODE
            export TF_VAR_vm_cpu=$DEPLOY_CPU
            export TF_VAR_vm_mem=$DEPLOY_MEM
            export TF_VAR_vm_disk=$DEPLOY_DISK
            if [ -n "$DEPLOY_DISK_TYPE" ]; then
                export TF_VAR_vm_disk_type=$DEPLOY_DISK_TYPE
            fi
            log_warning "Unknown pattern '$PATTERN_NAME', using generic vm_* variables"
            ;;
    esac
    
    log_success "Configuration complete"
    echo ""

    # Show concise deployment summary so operators can verify settings
    log_step "Deployment configuration summary"
    log_info "App: $APP_NAME v$APP_VERSION ($PATTERN_NAME pattern)"
    
    if [ "$PATTERN_NAME" = "k3s" ]; then
        # K3s-specific summary
        log_info "Cluster: $K3S_CONTROL_COUNT control + $K3S_WORKER_COUNT worker + $K3S_INGRESS_COUNT ingress nodes"
        log_info "Management: node $TF_VAR_management_node"
        log_info "Control nodes: $TF_VAR_control_nodes"
        log_info "Worker nodes: $TF_VAR_worker_nodes"
        [ "$K3S_INGRESS_COUNT" -gt 0 ] && log_info "Ingress nodes: $TF_VAR_ingress_nodes (public IPv4)"
    else
        # Single-node summary
        local ipv4_status="disabled"
        if [ "${DEPLOY_IPV4:-false}" = "true" ]; then
            ipv4_status="enabled"
        fi
        local disk_type_summary="${DEPLOY_DISK_TYPE:-auto}"
        log_info "Node: $DEPLOY_NODE (grid network: ${DEPLOY_NETWORK:-main})"
        log_info "Resources: CPU=${DEPLOY_CPU} vcores, MEM=${DEPLOY_MEM}MB, DISK=${DEPLOY_DISK}GB (type=${disk_type_summary})"
        log_info "Public IPv4: $ipv4_status"
    fi
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

    if [ -n "$DEPLOY_DISK_TYPE" ]; then
        echo "deploy_disk_type: $DEPLOY_DISK_TYPE" >> "$STATE_DIR/state.yaml"
    fi
    echo "deploy_ipv4: $DEPLOY_IPV4" >> "$STATE_DIR/state.yaml"
    
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

    # Step 2.4: Capture real IP addresses from terraform outputs (logging only; state.yaml is populated by terraform task)
    log_step "Capturing deployment IP addresses..."
    if [ -d "$STATE_DIR/terraform" ] && [ -f "$STATE_DIR/terraform/terraform.tfstate" ]; then
        cd "$STATE_DIR/terraform" || return 1

        # Capture primary IP for logging (public or WireGuard, depending on pattern)
        local real_primary_ip=""
        local real_primary_type=""
        real_primary_ip=$(terraform output -raw primary_ip 2>/dev/null || echo "")
        real_primary_type=$(terraform output -raw primary_ip_type 2>/dev/null || echo "")

        if [ -n "$real_primary_ip" ] && [ "$real_primary_ip" != "null" ]; then
            # Strip CIDR if present for cleaner logging
            local display_primary_ip
            display_primary_ip=$(echo "$real_primary_ip" | cut -d'/' -f1)

            if [ -n "$real_primary_type" ] && [ "$real_primary_type" != "null" ]; then
                log_success "Captured primary IP ($real_primary_type): $display_primary_ip"
            else
                log_success "Captured primary IP: $display_primary_ip"
            fi
        else
            log_warning "Could not extract primary IP from terraform output"
        fi

        # Capture Mycelium IPv6 for logging
        local real_mycelium_ip=""
        real_mycelium_ip=$(terraform output -raw mycelium_ip 2>/dev/null || echo "")

        if [ -n "$real_mycelium_ip" ] && [ "$real_mycelium_ip" != "null" ] && [ "$real_mycelium_ip" != "<nil>" ]; then
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
    # K3s pattern has its own multi-node inventory generator
    if [ "$PATTERN_NAME" = "k3s" ] && [ -f "$PATTERN_DIR/scripts/generate-inventory.sh" ]; then
        log_step "Generating K3s multi-node inventory..."
        
        # The K3s inventory generator needs to run from the pattern directory
        # and reads terraform state from infrastructure/
        local k3s_infra_dir="$STATE_DIR/terraform"
        local k3s_platform_dir="$STATE_DIR/ansible"
        
        # Create platform directory if needed
        mkdir -p "$k3s_platform_dir"
        
        # Copy the generate-inventory script and run it with proper paths
        # We need to generate inventory that points to the terraform state in our state dir
        if ! generate_k3s_inventory "$STATE_DIR" "$k3s_platform_dir"; then
            log_error "Failed to generate K3s inventory"
            return 1
        fi
        
        # Copy inventory to state dir root for ansible.sh
        if [ -f "$k3s_platform_dir/inventory.ini" ]; then
            cp "$k3s_platform_dir/inventory.ini" "$STATE_DIR/inventory.ini"
        fi
    else
        if ! bash "$DEPLOYER_ROOT/core/tasks/inventory.sh"; then
            log_error "Failed to generate Ansible inventory"
            return 1
        fi
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
    local primary_ip_type=""

    # Read primary IP type from state (public/wireguard/mycelium)
    if [ -f "$STATE_DIR/state.yaml" ]; then
        primary_ip_type=$(grep "^primary_ip_type:" "$STATE_DIR/state.yaml" 2>/dev/null | head -n1 | awk '{print $2}')
    fi

    # DNS automation: create A record when DOMAIN/DNS_PROVIDER are configured
    # Only attempt DNS when we have a public IPv4 address
    if [ -n "$vm_ip" ] && [ "$primary_ip_type" = "public" ]; then
        # Derive domain from common env vars used by apps/patterns
        local dns_domain=""
        if [ -n "${TFGRID_DOMAIN:-}" ]; then
            dns_domain="$TFGRID_DOMAIN"
        elif [ -n "${DOMAIN:-}" ]; then
            dns_domain="$DOMAIN"
        elif [ -n "${DOMAIN_NAME:-}" ]; then
            dns_domain="$DOMAIN_NAME"
        fi

        # Only attempt DNS automation for real domains (not localhost/IP) and non-manual provider
        if [ -n "$dns_domain" ] && [ -n "${DNS_PROVIDER:-}" ] && [ "${DNS_PROVIDER:-manual}" != "manual" ]; then
            if [ "$dns_domain" != "localhost" ] && ! [[ "$dns_domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                log_step "Setting up DNS for $dns_domain -> $vm_ip (provider: $DNS_PROVIDER)"

                if create_dns_record "$dns_domain" "$vm_ip"; then
                    # DNS propagation is helpful for HTTPS challenges but should not block deployment
                    if command -v dig >/dev/null 2>&1; then
                        if ! verify_dns_propagation "$dns_domain" "$vm_ip" 12 5; then
                            log_warning "DNS propagation not yet complete for $dns_domain. Continuing deployment."
                        fi
                    else
                        log_info "dig command not found; skipping DNS propagation verification."
                    fi
                else
                    log_warning "DNS record creation failed for $dns_domain. Continuing deployment."
                fi
            fi
        fi
    fi

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
    
    # Mark deployment as active (tracked by deployment ID)
    mark_deployment_active "$DEPLOYMENT_ID"
    
    # Perform health check to verify deployment
    log_info "Performing health check..."
    if ! perform_deployment_health_check "$DEPLOYMENT_ID" "$PATTERN_NAME"; then
        log_warning "Health check failed - deployment may not be fully functional"
        mark_deployment_failed "$DEPLOYMENT_ID" "Health check failed after deployment"
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

    # Automatically set this deployment as the active context for UX convenience
    local current_app_file="$HOME/.config/tfgrid-compose/current-app"
    mkdir -p "$(dirname "$current_app_file")"
    echo "$DEPLOYMENT_ID" > "$current_app_file"
    log_info "Active deployment context set to: $DEPLOYMENT_ID"
    echo ""

    # If JSON output was requested (for programmatic callers like control planes),
    # emit a final machine-readable summary line that external tools can parse
    # without depending on log formatting.
    if [ "${TFGRID_OUTPUT_FORMAT:-}" = "json" ]; then
        # Prefer primary_ip from state.yaml, fall back to network-aware resolution
        local primary_ip=""
        local mycelium_ip=""

        if [ -f "$STATE_DIR/state.yaml" ]; then
            primary_ip=$(grep "^primary_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')
            mycelium_ip=$(grep "^mycelium_ip:" "$STATE_DIR/state.yaml" 2>/dev/null | awk '{print $2}')
        fi

        if [ -z "$primary_ip" ]; then
            primary_ip=$(get_deployment_ip "$DEPLOYMENT_ID")
        fi

        # Build minimal JSON payload. Use deploymentId/primaryIp/myceliumIp keys
        # to match control-plane orchestrator expectations.
        local json="{\"deploymentId\":\"$DEPLOYMENT_ID\""
        if [ -n "$primary_ip" ]; then
            json="$json,\"primaryIp\":\"$primary_ip\""
        fi
        if [ -n "$mycelium_ip" ]; then
            json="$json,\"myceliumIp\":\"$mycelium_ip\""
        fi
        if [ -n "$contract_id" ]; then
            json="$json,\"contractId\":\"$contract_id\""
        fi
        json="$json}"

        echo "$json"
    fi

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
    
    # If manifest doesn't define a mode, fall back to global network mode preference
    if [ -z "$network_mode" ] || [ "$network_mode" = "null" ]; then
        # get_global_network_mode is defined in core/network.sh, which is sourced by the CLI
        if command -v get_global_network_mode >/dev/null 2>&1; then
            network_mode=$(get_global_network_mode)
        fi
    fi
    
    # Export network configuration (use manifest values or defaults)
    export TF_VAR_tfgrid_network="${TF_VAR_tfgrid_network:-main}"
    export MAIN_NETWORK="${main_network:-${MAIN_NETWORK:-wireguard}}"
    export INTER_NODE_NETWORK="${inter_node_network:-${INTER_NODE_NETWORK:-wireguard}}"
    export NETWORK_MODE="${network_mode:-wireguard-only}"
    export TF_VAR_network_mode="$NETWORK_MODE"
    
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

    # Copy state.yaml to VM for IP access during configuration
    log_info "Copying deployment state..."
    if ! scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        "$STATE_DIR/state.yaml" "root@$scp_host:/tmp/app-deployment/state.yaml" 2>/dev/null; then
        log_error "Failed to copy state.yaml to VM ($scp_host)"
        return 1
    fi

    # Copy app .env to VM so hooks can load the same configuration
    if [ -f "$APP_DIR/.env" ]; then
        log_info "Copying app .env to VM..."
        if ! scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "$APP_DIR/.env" "root@$scp_host:/tmp/app-source/.env" 2>/dev/null; then
            log_warning "Failed to copy .env to VM ($scp_host)"
        else
            log_success ".env copied to VM"
        fi
    else
        log_info "No .env found in app directory; skipping .env copy"
    fi

    # Copy prebuilt artifacts tarball to VM if present (optional, app-specific)
    local artifacts_source=""
    if [ -n "${APP_ARTIFACT_TARBALL:-}" ]; then
        artifacts_source="$APP_ARTIFACT_TARBALL"
    else
        artifacts_source="$APP_DIR/artifacts/latest.tar.gz"
    fi

    if [ -n "$artifacts_source" ] && [ -f "$artifacts_source" ]; then
        log_info "Copying app artifacts tarball to VM from $artifacts_source..."
        if ! scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "$artifacts_source" "root@$scp_host:/tmp/app-source/artifacts.tar.gz" 2>/dev/null; then
            log_warning "Failed to copy artifacts tarball to VM ($scp_host)"
        else
            log_success "Artifacts tarball copied to VM"
        fi
    else
        log_info "No artifacts tarball found for app; skipping artifacts copy"
    fi

    # Copy VM-side helper for IP resolution so hooks can use network preference
    if [ -f "$DEPLOYER_ROOT/scripts/get_deployment_ip_vm.sh" ]; then
        log_info "Copying get_deployment_ip_vm helper to VM..."
        if ! scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "$DEPLOYER_ROOT/scripts/get_deployment_ip_vm.sh" "root@$scp_host:/tmp/app-deployment/get_deployment_ip_vm.sh" 2>/dev/null; then
            log_warning "Failed to copy get_deployment_ip_vm helper to VM ($scp_host)"
        else
            log_success "get_deployment_ip_vm helper copied to VM"
        fi
    fi

    log_success "Deployment hooks and state copied to VM"

    # Copy app source directory contents if it exists (for scripts, templates, etc.)
    if [ -d "$APP_DIR/src" ]; then
        log_info "Copying app source files from src/..."
        if ! scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "$APP_DIR"/src/* "root@$scp_host:/tmp/app-source/" 2>/dev/null; then
            log_error "Failed to copy app source files to VM ($scp_host)"
            return 1
        fi
        log_success "App source files copied to VM"
    fi

    # Copy essential app files (docker-compose.yaml, scripts/, etc.) from app root
    log_info "Copying essential app files..."
    local copied_files=0
    
    # Copy docker-compose.yaml if exists
    if [ -f "$APP_DIR/docker-compose.yaml" ]; then
        if scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "$APP_DIR/docker-compose.yaml" "root@$scp_host:/tmp/app-source/" 2>/dev/null; then
            ((copied_files++))
        fi
    fi
    
    # Copy scripts directory if exists
    if [ -d "$APP_DIR/scripts" ]; then
        if scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "$APP_DIR/scripts" "root@$scp_host:/tmp/app-source/" 2>/dev/null; then
            ((copied_files++))
        fi
    fi
    
    # Copy config directory if exists
    if [ -d "$APP_DIR/config" ]; then
        if scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "$APP_DIR/config" "root@$scp_host:/tmp/app-source/" 2>/dev/null; then
            ((copied_files++))
        fi
    fi
    
    # Copy templates directory if exists
    if [ -d "$APP_DIR/templates" ]; then
        if scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            "$APP_DIR/templates" "root@$scp_host:/tmp/app-source/" 2>/dev/null; then
            ((copied_files++))
        fi
    fi
    
    if [ $copied_files -gt 0 ]; then
        log_success "Copied $copied_files essential app files/directories to VM"
    else
        log_info "No essential app files to copy from app root"
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

    # Pass application version from manifest so hooks can derive release layout
    if [ -n "${APP_VERSION:-}" ]; then
        env_vars="$env_vars export APP_VERSION='$APP_VERSION';"
        log_info "Passing app version to deployment hooks: $APP_VERSION"
    fi

    # Pass network preference to deployment hooks
    local network_preference=$(get_network_preference "$DEPLOYMENT_ID")
    env_vars="$env_vars export DEPLOYMENT_NETWORK_PREFERENCE='$network_preference';"
    log_info "Passing network preference to deployment hooks: $network_preference"
    
    # Derive canonical domain for hooks (used by apps like tfgrid-wordpress
    # to configure Caddy and TLS inside the VM). Prefer TFGRID_DOMAIN, then
    # DOMAIN, then DOMAIN_NAME.
    local hook_domain=""
    if [ -n "${TFGRID_DOMAIN:-}" ]; then
        hook_domain="$TFGRID_DOMAIN"
    elif [ -n "${DOMAIN:-}" ]; then
        hook_domain="$DOMAIN"
    elif [ -n "${DOMAIN_NAME:-}" ]; then
        hook_domain="$DOMAIN_NAME"
    fi

    if [ -n "$hook_domain" ]; then
        env_vars="$env_vars export TFGRID_DOMAIN='$hook_domain'; export DOMAIN='$hook_domain';"
        log_info "Passing domain to deployment hooks: $hook_domain"
    fi

    # Derive SSL email for ACME/Let’s Encrypt. Prefer TFGRID_SSL_EMAIL, then
    # SSL_EMAIL.
    local hook_ssl_email=""
    if [ -n "${TFGRID_SSL_EMAIL:-}" ]; then
        hook_ssl_email="$TFGRID_SSL_EMAIL"
    elif [ -n "${SSL_EMAIL:-}" ]; then
        hook_ssl_email="$SSL_EMAIL"
    fi

    if [ -n "$hook_ssl_email" ]; then
        env_vars="$env_vars export TFGRID_SSL_EMAIL='$hook_ssl_email'; export SSL_EMAIL='$hook_ssl_email';"
        log_info "Passing SSL email to deployment hooks: $hook_ssl_email"
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
        # Verbose mode: Show ALL output in real-time with TTY for unbuffered streaming
        ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "cd /tmp/app-deployment && chmod +x setup.sh && $env_vars ./setup.sh" 2>&1 | tee "$STATE_DIR/hook-setup.log"
        local setup_status=${PIPESTATUS[0]}
        if [ "$setup_status" -ne 0 ]; then
            log_error "Setup hook failed. Check: $STATE_DIR/hook-setup.log"
            return 1
        fi
    else
        # Normal mode: Show milestone lines (emoji prefixed) while logging everything
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "cd /tmp/app-deployment && chmod +x setup.sh && $env_vars ./setup.sh" 2>&1 | \
            tee "$STATE_DIR/hook-setup.log" | \
            grep -E '^[[:space:]]*(🚀|📦|🐳|🔧|🌐|📁|📋|🔐|✅|❌|⚠|ℹ|→|▶)' || true
        local setup_status=${PIPESTATUS[0]}
        if [ "$setup_status" -ne 0 ]; then
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
        # Verbose mode: Show ALL output in real-time with TTY for unbuffered streaming
        ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "cd /tmp/app-deployment && chmod +x configure.sh && $env_vars ./configure.sh" 2>&1 | tee "$STATE_DIR/hook-configure.log"
        local configure_status=${PIPESTATUS[0]}
        if [ "$configure_status" -ne 0 ]; then
            if [ "$configure_optional" = "true" ]; then
                log_warning "Configure hook failed (optional). Check: $STATE_DIR/hook-configure.log"
            else
                log_error "Configure hook failed. Check: $STATE_DIR/hook-configure.log"
                return 1
            fi
        fi
    else
        # Normal mode: Show milestone lines (emoji prefixed) while logging everything
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "cd /tmp/app-deployment && chmod +x configure.sh && $env_vars ./configure.sh" 2>&1 | \
            tee "$STATE_DIR/hook-configure.log" | \
            grep -E '^[[:space:]]*(🚀|📦|🐳|🔧|🌐|📁|📋|🔐|✅|❌|⚠|ℹ|→|▶)' || true
        local configure_status=${PIPESTATUS[0]}
        if [ "$configure_status" -ne 0 ]; then
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
        # Verbose mode: Show ALL output in real-time with TTY for unbuffered streaming
        ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "cd /tmp/app-deployment && chmod +x healthcheck.sh && ./healthcheck.sh" 2>&1 | tee "$STATE_DIR/hook-healthcheck.log"
        local health_status=${PIPESTATUS[0]}
        if [ "$health_status" -ne 0 ]; then
            log_warning "Health check had issues. Check: $STATE_DIR/hook-healthcheck.log"
            # Don't fail on healthcheck issues
        else
            log_success "Health check passed"
        fi
    else
        # Normal mode: Show milestone lines (emoji prefixed) while logging everything
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
            root@$vm_ip "cd /tmp/app-deployment && chmod +x healthcheck.sh && ./healthcheck.sh" 2>&1 | \
            tee "$STATE_DIR/hook-healthcheck.log" | \
            grep -E '^[[:space:]]*(🚀|📦|🐳|🔧|🌐|📁|📋|🔐|✅|❌|⚠|ℹ|→|▶)' || true
        local health_status=${PIPESTATUS[0]}
        if [ "$health_status" -ne 0 ]; then
            log_warning "Health check had issues. Check: $STATE_DIR/hook-healthcheck.log"
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
