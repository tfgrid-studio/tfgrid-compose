#!/usr/bin/env bash
# Contract Manager - Simple tfcmd wrapper for TFGrid Compose

# Load dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Check if tfcmd is installed
check_tfcmd_installed() {
    if ! command -v tfcmd >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

# Check if tfcmd is logged in
check_tfcmd_logged_in() {
    if ! check_tfcmd_installed; then
        return 1
    fi
    
    if ! tfcmd login status >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

# Simple wrapper for tfcmd get contracts
contracts_list() {
    log_info "Fetching contracts via tfcmd..."
    
    if ! check_tfcmd_installed; then
        log_error "tfcmd not installed"
        log_info "Install tfcmd with: tfgrid-compose tfcmd-install"
        return 1
    fi
    
    if ! check_tfcmd_logged_in; then
        log_error "tfcmd not logged in"
        log_info "Login to tfcmd with: tfgrid-compose tfcmd-login"
        return 1
    fi
    
    # Call tfcmd to get contracts
    if ! tfcmd get contracts; then
        log_error "Failed to fetch contracts via tfcmd"
        return 1
    fi
    
    return 0
}

# Simple wrapper for tfcmd delete contracts
contracts_delete() {
    local contract_id="$1"
    
    if [ -z "$contract_id" ]; then
        log_error "Contract ID required"
        echo ""
        echo "Usage: tfgrid-compose contracts delete <contract-id>"
        return 1
    fi
    
    log_info "Deleting contract $contract_id via tfcmd..."
    
    if ! check_tfcmd_installed; then
        log_error "tfcmd not installed"
        log_info "Install tfcmd with: tfgrid-compose tfcmd-install"
        return 1
    fi
    
    if ! check_tfcmd_logged_in; then
        log_error "tfcmd not logged in"
        log_info "Login to tfcmd with: tfgrid-compose tfcmd-login"
        return 1
    fi
    
    # Call tfcmd to delete contract
    if ! tfcmd delete contracts "$contract_id"; then
        log_error "Failed to delete contract $contract_id via tfcmd"
        return 1
    fi
    
    log_success "Contract $contract_id deleted successfully"
    return 0
}