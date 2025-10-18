#!/usr/bin/env bash
# Validation functions for tfgrid-compose

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Auto-detect and load ThreeFold mnemonic
# Priority: env var > standard location > project-specific > error
load_mnemonic() {
    # Priority 1: Already set via environment variable
    if [ -n "$TF_VAR_mnemonic" ]; then
        return 0
    fi
    
    # Priority 2: Standard ThreeFold location
    local standard_path="$HOME/.config/threefold/mnemonic"
    if [ -f "$standard_path" ]; then
        # Check file permissions for security
        local perms=$(stat -c %a "$standard_path" 2>/dev/null || stat -f %A "$standard_path" 2>/dev/null || echo "644")
        if [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
            log_warning "Mnemonic file has insecure permissions: $perms"
            log_info "Recommended: chmod 600 $standard_path"
        fi
        
        export TF_VAR_mnemonic=$(cat "$standard_path")
        return 0
    fi
    
    # Priority 3: Project-specific mnemonic (git ignored)
    local project_path="./.tfgrid-mnemonic"
    if [ -f "$project_path" ]; then
        log_info "Using project-specific mnemonic: $project_path"
        export TF_VAR_mnemonic=$(cat "$project_path")
        return 0
    fi
    
    # Not found - provide helpful error
    echo ""
    log_error "ThreeFold mnemonic not configured"
    echo ""
    echo "You need to login with your ThreeFold wallet:"
    echo "  tfgrid-compose login"
    echo ""
    echo "Need help? See the setup guide:"
    echo "  → tfgrid-compose docs"
    echo "  → https://docs.tfgrid.studio/getting-started/threefold-setup"
    log_info ""    
    echo ""
    echo "  Option 1 (Recommended): Use standard ThreeFold location"
    echo "    mkdir -p ~/.config/threefold"
    echo "    echo 'your-mnemonic-here' > ~/.config/threefold/mnemonic"
    echo "    chmod 600 ~/.config/threefold/mnemonic"
    echo ""
    echo "  Option 2: Set environment variable (one session)"
    echo "    export TF_VAR_mnemonic=\$(cat ~/.config/threefold/mnemonic)  # Bash/Zsh"
    echo "    set -x TF_VAR_mnemonic (cat ~/.config/threefold/mnemonic)    # Fish"
    echo ""
    echo "  Option 3: Project-specific (git ignored)"
    echo "    echo 'your-mnemonic-here' > .tfgrid-mnemonic"
    echo "    chmod 600 .tfgrid-mnemonic"
    echo ""
    return 1
}

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Validate system prerequisites
validate_prerequisites() {
    local missing=0
    local warnings=0
    
    log_step "Validating system prerequisites..."
    
    # Check Terraform/OpenTofu (prefer OpenTofu as it's open source)
    if command_exists tofu; then
        export TF_CMD="tofu"
        log_success "OpenTofu found: $(tofu --version | head -1)"
    elif command_exists terraform; then
        export TF_CMD="terraform"
        log_success "Terraform found: $(terraform --version | head -1)"
    else
        echo ""
        log_error "Terraform or OpenTofu is required"
        echo ""
        echo "Install options:"
        echo "  OpenTofu (recommended): https://opentofu.org/docs/intro/install/"
        echo "  Terraform: https://www.terraform.io/downloads"
        echo ""
        missing=1
    fi
    
    # Check Ansible
    if command_exists ansible-playbook; then
        log_success "Ansible found: $(ansible --version | head -1)"
    else
        echo ""
        log_error "Ansible is required"
        echo ""
        echo "Install:"
        echo "  Ubuntu/Debian: sudo apt install ansible"
        echo "  macOS: brew install ansible"
        echo "  Docs: https://docs.ansible.com/ansible/latest/installation_guide/"
        echo ""
        missing=1
    fi
    
    # Check SSH
    if command_exists ssh; then
        log_success "SSH client found"
    else
        echo ""
        log_error "SSH client is required"
        echo ""
        echo "Install:"
        echo "  Ubuntu/Debian: sudo apt install openssh-client"
        echo "  macOS: Built-in (should already have ssh)"
        echo ""
        missing=1
    fi
    
    # Check WireGuard (warning only, not all patterns need it)
    if command_exists wg; then
        log_success "WireGuard found"
    else
        log_warning "WireGuard not found (required for some patterns)"
        log_info "Install on Ubuntu/Debian: sudo apt install wireguard"
        log_info "Install on macOS: brew install wireguard-tools"
        warnings=1
    fi
    
    # Auto-detect and load mnemonic (priority order)
    if ! load_mnemonic; then
        return 1
    fi
    log_success "ThreeFold mnemonic configured"
    
    # Summary
    echo ""
    if [ $missing -gt 0 ]; then
        log_error "Missing required dependencies"
        log_info "See docs/QUICKSTART.md for setup instructions"
        return 1
    fi
    
    if [ $warnings -gt 0 ]; then
        log_warning "Some optional tools missing, but proceeding..."
    fi
    
    log_success "All prerequisites validated"
    return 0
}

# Validate app path
validate_app_path() {
    local app_path="$1"
    
    if [ -z "$app_path" ]; then
        echo ""
        log_error "App name or path is required"
        echo ""
        echo "Usage:"
        echo "  tfgrid-compose up <app-name>     # From registry"
        echo "  tfgrid-compose up <app-path>     # Local app"
        echo ""
        echo "Examples:"
        echo "  tfgrid-compose up tfgrid-ai-agent"
        echo "  tfgrid-compose up ./my-app"
        echo ""
        echo "Browse available apps:"
        echo "  tfgrid-compose search"
        echo ""
        return 1
    fi
    
    if [ ! -d "$app_path" ]; then
        echo ""
        log_error "App directory not found: $app_path"
        echo ""
        echo "Check:"
        echo "  1. Path is correct"
        echo "  2. Directory exists"
        echo "  3. You're in the right location"
        echo ""
        echo "Browse registry apps:"
        echo "  tfgrid-compose search"
        echo ""
        return 1
    fi
    
    if [ ! -f "$app_path/tfgrid-compose.yaml" ]; then
        echo ""
        log_error "App manifest not found"
        echo ""
        echo "Expected: $app_path/tfgrid-compose.yaml"
        echo ""
        echo "Every app needs a tfgrid-compose.yaml file."
        echo "Learn more:"
        echo "  → tfgrid-compose docs"
        echo "  → https://docs.tfgrid.studio/development/pattern-contract"
        echo ""
        return 1
    fi
    
    return 0
}

# Validate pattern name
validate_pattern_name() {
    local pattern_name="$1"
    local patterns_dir="$2"
    
    if [ -z "$pattern_name" ]; then
        log_error "Pattern name not specified"
        return 1
    fi
    
    if [ ! -d "$patterns_dir/$pattern_name" ]; then
        log_error "Pattern not found: $pattern_name"
        log_info "Available patterns:"
        for pattern in "$patterns_dir"/*; do
            if [ -d "$pattern" ]; then
                log_info "  - $(basename "$pattern")"
            fi
        done
        return 1
    fi
    
    return 0
}

# Validate state directory for commands that need existing deployment
validate_deployment_exists() {
    # Derive app name from APP_PATH or APP_NAME
    local app_name="${APP_NAME}"
    if [ -z "$app_name" ] && [ -n "$APP_PATH" ]; then
        app_name=$(basename "$APP_PATH")
    fi
    
    if [ -z "$app_name" ]; then
        log_error "Cannot determine app name"
        return 1
    fi
    
    # Construct state directory path
    local state_dir="${STATE_DIR:-$STATE_BASE_DIR/$app_name}"
    
    if [ ! -d "$state_dir" ]; then
        log_error "No deployment found for: $app_name"
        log_info "State directory not found: $state_dir"
        log_info "Deploy first with: tfgrid-compose up $app_name"
        return 1
    fi
    
    if [ ! -f "$state_dir/state.yaml" ]; then
        log_error "Deployment state corrupted for: $app_name"
        log_info "State file not found: $state_dir/state.yaml"
        log_info "Try cleaning and redeploying: tfgrid-compose down $app_name && tfgrid-compose up $app_name"
        return 1
    fi
    
    return 0
}

# Validate no existing deployment (for fresh deployments)
validate_no_deployment() {
    local state_dir="${STATE_DIR:-.tfgrid-compose}"
    
    if [ -d "$state_dir" ] && [ -f "$state_dir/state.yaml" ]; then
        log_warning "Existing deployment detected"
        
        # Show current deployment info
        local app_name=$(grep "^app_name:" "$state_dir/state.yaml" 2>/dev/null | awk '{print $2}')
        local deployment_id=$(grep "^deployment_id:" "$state_dir/state.yaml" 2>/dev/null | awk '{print $2}')
        
        if [ -n "$app_name" ]; then
            log_info "Current deployment: $app_name (ID: $deployment_id)"
        fi
        
        log_error "Cannot deploy while another deployment exists"
        log_info "Options:"
        log_info "  1. Destroy existing: tfgrid-compose down <app-dir>"
        log_info "  2. Check status: tfgrid-compose status <app-dir>"
        log_info "  3. Force clean (dangerous): tfgrid-compose clean <app-dir>"
        return 1
    fi
    
    return 0
}

# Validate user has sudo access (needed for WireGuard)
validate_sudo_access() {
    if ! sudo -n true 2>/dev/null; then
        log_warning "Sudo access required for WireGuard setup"
        log_info "You may be prompted for your password"
    fi
    return 0
}

# Check if WireGuard is needed based on network config
needs_wireguard() {
    local main_network="$1"
    local inter_node="$2"
    
    [[ "$main_network" == "wireguard" ]] || [[ "$inter_node" == "wireguard" ]]
}

# Check if Mycelium is needed based on network config
needs_mycelium() {
    local main_network="$1"
    local inter_node="$2"
    local mode="$3"
    
    [[ "$main_network" == "mycelium" ]] || 
    [[ "$inter_node" == "mycelium" ]] || 
    [[ "$mode" == "mycelium-only" ]] ||
    [[ "$mode" == "both" ]]
}

# Test Mycelium connectivity by pinging public nodes
check_mycelium_connectivity() {
    log_info "Testing Mycelium connectivity..."
    
    # Public nodes from https://github.com/threefoldtech/mycelium README
    local test_nodes=(
        "54b:83ab:6cb5:7b38:44ae:cd14:53f3:a907"  # DE Node 01
        "40a:152c:b85b:9646:5b71:d03a:eb27:2462"  # DE Node 02
        "597:a4ef:806:b09:6650:cbbf:1b68:cc94"   # BE Node 03
        "549:8bce:fa45:e001:cbf8:f2e2:2da6:a67c"  # BE Node 04
        "410:2778:53bf:6f41:af28:1b60:d7c0:707a"  # FI Node 05
    )
    
    # Test sequentially, stop at first success
    for node in "${test_nodes[@]}"; do
        if ping6 -c 1 -W 2 "$node" >/dev/null 2>&1; then
            log_success "Mycelium connectivity verified (reached $node)"
            return 0
        fi
    done
    
    # All nodes failed
    log_warning "Could not reach any Mycelium public nodes"
    log_info "This may indicate:"
    echo "  - Mycelium daemon not running (try: sudo systemctl start mycelium)"
    echo "  - Firewall blocking IPv6 connections"
    echo "  - Network configuration issues"
    return 1
}

# Validate network prerequisites based on manifest configuration
validate_network_prerequisites() {
    local main_network="$1"
    local inter_node="$2"
    local mode="$3"
    
    log_step "Checking network requirements..."
    log_info "Network config: main=$main_network, inter_node=$inter_node, mode=$mode"
    echo ""
    
    local has_errors=0
    
    # Check WireGuard if needed
    if needs_wireguard "$main_network" "$inter_node"; then
        if ! command -v wg >/dev/null 2>&1; then
            log_error "WireGuard required but not installed"
            log_info "Install on Ubuntu/Debian: sudo apt install wireguard"
            log_info "Install on macOS: brew install wireguard-tools"
            has_errors=1
        else
            wg_version=$(wg --version 2>&1 | head -1)
            log_success "WireGuard found: $wg_version"
        fi
    fi
    
    # Check Mycelium if needed
    if needs_mycelium "$main_network" "$inter_node" "$mode"; then
        if ! command -v mycelium >/dev/null 2>&1; then
            log_error "Mycelium required but not installed"
            log_info "Install from: https://github.com/threefoldtech/mycelium"
            has_errors=1
        else
            mycelium_version=$(mycelium --version 2>&1 | head -1)
            log_success "Mycelium found: $mycelium_version"
            
            # Test connectivity (warn only, don't fail)
            if ! check_mycelium_connectivity; then
                log_warning "Mycelium connectivity test failed - deployment may have issues"
            fi
        fi
    fi
    
    echo ""
    if [ $has_errors -gt 0 ]; then
        log_error "Network requirements not met"
        return 1
    fi
    
    log_success "All network requirements satisfied"
    return 0
}

# Export functions
export -f command_exists
export -f load_mnemonic
export -f validate_prerequisites
export -f validate_directory
export -f validate_file
export -f validate_app_path
export -f validate_deployment_exists
export -f validate_no_deployment
export -f validate_sudo_access
export -f needs_wireguard
export -f needs_mycelium
export -f check_mycelium_connectivity
export -f validate_network_prerequisites
