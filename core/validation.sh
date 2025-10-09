#!/usr/bin/env bash
# Validation module - Check prerequisites and inputs

# Check if a command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Validate system prerequisites
validate_prerequisites() {
    local missing=0
    local warnings=0
    
    log_step "Validating system prerequisites..."
    
    # Check Terraform
    if command_exists terraform; then
        log_success "Terraform found: $(terraform --version | head -1)"
    elif command_exists tofu; then
        log_success "OpenTofu found: $(tofu --version | head -1)"
    else
        log_error "Terraform/OpenTofu not found"
        log_info "Install: https://www.terraform.io/downloads"
        log_info "Or OpenTofu: https://opentofu.org/docs/intro/install/"
        missing=1
    fi
    
    # Check Ansible
    if command_exists ansible-playbook; then
        log_success "Ansible found: $(ansible --version | head -1)"
    else
        log_error "Ansible not found"
        log_info "Install on Ubuntu/Debian: sudo apt install ansible"
        log_info "Install on macOS: brew install ansible"
        missing=1
    fi
    
    # Check SSH
    if command_exists ssh; then
        log_success "SSH client found"
    else
        log_error "SSH client not found"
        log_info "Install: sudo apt install openssh-client"
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
    
    # Check for mnemonic
    if [ -f ~/.config/threefold/mnemonic ]; then
        log_success "ThreeFold mnemonic configured"
    else
        log_error "ThreeFold mnemonic not found"
        log_info "Create: mkdir -p ~/.config/threefold"
        log_info "Add: echo 'your mnemonic' > ~/.config/threefold/mnemonic"
        log_info "Secure: chmod 600 ~/.config/threefold/mnemonic"
        missing=1
    fi
    
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
        log_error "App path not specified"
        log_info "Usage: tfgrid-compose up <app-path>"
        return 1
    fi
    
    if [ ! -d "$app_path" ]; then
        log_error "App directory not found: $app_path"
        return 1
    fi
    
    if [ ! -f "$app_path/tfgrid-compose.yaml" ]; then
        log_error "App manifest not found: $app_path/tfgrid-compose.yaml"
        log_info "Every app needs a tfgrid-compose.yaml manifest"
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
    local state_dir="${STATE_DIR:-.tfgrid-compose}"
    
    if [ ! -d "$state_dir" ]; then
        log_error "No deployment found"
        log_info "State directory not found: $state_dir"
        log_info "Deploy first with: make up APP=<app-path>"
        return 1
    fi
    
    if [ ! -f "$state_dir/state.yaml" ]; then
        log_error "Deployment state corrupted"
        log_info "State file not found: $state_dir/state.yaml"
        log_info "Try cleaning and redeploying: make clean && make up"
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
        log_info "  1. Destroy existing: make down APP=<app>"
        log_info "  2. Check status: make status APP=<app>"
        log_info "  3. Force clean (dangerous): make clean"
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

# Export functions
export -f command_exists
export -f validate_prerequisites
export -f validate_app_path
export -f validate_pattern_name
export -f validate_deployment_exists
export -f validate_no_deployment
export -f validate_sudo_access
