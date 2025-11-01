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

# Load tfgrid-compose credentials
load_tfgrid_credentials() {
    # Load tfgrid-compose credentials
    if ! source "$SCRIPT_DIR/login.sh" 2>/dev/null; then
        log_error "Could not load login.sh"
        return 1
    fi
    
    if ! load_credentials; then
        log_error "Failed to load credentials"
        return 1
    fi
    
    if [ -z "$TFGRID_MNEMONIC" ]; then
        log_error "ThreeFold mnemonic not configured"
        log_info "Run 'tfgrid-compose login' to configure credentials"
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
    
    # Load credentials and use mnemonic directly
    if ! load_tfgrid_credentials; then
        return 1
    fi
    
    # Call tfcmd to get contracts using mnemonic
    if ! echo "$TFGRID_MNEMONIC" | tfcmd get contracts; then
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
    
    # Load credentials and use mnemonic directly
    if ! load_tfgrid_credentials; then
        return 1
    fi
    
    # Call tfcmd to delete contract using mnemonic
    if ! echo "$TFGRID_MNEMONIC" | tfcmd cancel contracts "$contract_id"; then
        log_error "Failed to delete contract $contract_id via tfcmd"
        return 1
    fi
    
    log_success "Contract $contract_id deleted successfully"
    return 0
}

# Simple wrapper for tfcmd cancel all contracts
contracts_cancel_all() {
    log_warning "This will cancel ALL contracts associated with your mnemonic!"
    echo ""
    echo "Contracts that will be cancelled:"
    echo "  • All active node contracts"
    echo "  • All active rent contracts"
    echo "  • All active deployment contracts"
    echo ""
    
    read -p "Are you sure you want to cancel ALL contracts? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cancelled by user"
        return 0
    fi
    
    if ! check_tfcmd_installed; then
        log_error "tfcmd not installed"
        log_info "Install tfcmd with: tfgrid-compose tfcmd-install"
        return 1
    fi
    
    # Load credentials and use mnemonic directly
    if ! load_tfgrid_credentials; then
        return 1
    fi
    
    log_info "Cancelling ALL contracts via tfcmd..."
    echo ""
    echo "⚠️  This action cannot be undone!"
    echo ""
    
    # Call tfcmd to cancel all contracts using mnemonic
    if ! echo "$TFGRID_MNEMONIC" | tfcmd cancel contracts -a; then
        log_error "Failed to cancel contracts via tfcmd"
        return 1
    fi
    
    log_success "All contracts cancelled successfully"
    echo ""
    log_info "Note: This may take a few minutes to complete on the grid"
    return 0
}