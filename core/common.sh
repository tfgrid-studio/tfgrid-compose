#!/usr/bin/env bash
# Common utilities and shared functions for tfgrid-compose

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1"
}

log_step() {
    echo -e "${PURPLE}▶${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check required tools
check_requirements() {
    local missing=()
    
    # Check for Terraform or OpenTofu (prefer OpenTofu)
    if ! command_exists tofu && ! command_exists terraform; then
        missing+=("terraform/tofu")
    fi
    
    if ! command_exists ansible-playbook; then
        missing+=("ansible")
    fi
    
    if ! command_exists yq; then
        log_warning "yq not found, will use basic YAML parsing"
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        log_info "Please install: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Parse YAML (basic implementation without yq)
parse_yaml() {
    local file="$1"
    local prefix="$2"
    
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    fi
    
    # If yq is available, use it
    if command_exists yq; then
        # yq is available, use it for better parsing
        return 0
    fi
    
    # Basic parsing without yq (fallback)
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        # Simple key-value parsing
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Remove quotes
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            
            # Export as variable
            if [ -n "$prefix" ]; then
                export "${prefix}_${key}=${value}"
            else
                export "${key}=${value}"
            fi
        fi
    done < "$file"
}

# Get value from YAML file
yaml_get() {
    local file="$1"
    local key="$2"
    
    if ! command_exists yq; then
        # Fallback: grep-based extraction
        grep "^${key}:" "$file" | sed 's/^[^:]*:[[:space:]]*//' | sed 's/["\047]//g'
        return
    fi
    
    # Use yq for better extraction
    yq eval ".${key}" "$file" 2>/dev/null || echo ""
}

# Validate directory exists
validate_directory() {
    local dir="$1"
    local name="$2"
    
    if [ ! -d "$dir" ]; then
        log_error "$name directory not found: $dir"
        return 1
    fi
    
    return 0
}

# Validate file exists
validate_file() {
    local file="$1"
    local name="$2"
    
    if [ ! -f "$file" ]; then
        log_error "$name file not found: $file"
        return 1
    fi
    
    return 0
}

# Get script directory
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -h "$source" ]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}

# Get deployer root directory
get_deployer_root() {
    # Return the DEPLOYER_ROOT if already set
    if [ -n "$DEPLOYER_ROOT" ]; then
        echo "$DEPLOYER_ROOT"
        return
    fi
    
    # Try to find it from current script
    local source="${BASH_SOURCE[1]}"
    local dir="$(cd -P "$(dirname "$source")" && pwd)"
    
    # Go up until we find patterns/ directory
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/patterns" ]; then
            echo "$dir"
            return
        fi
        dir="$(dirname "$dir")"
    done
    
    # Fallback
    echo "$(pwd)"
}

# State directory
STATE_DIR=".tfgrid-compose"

# Create state directory
create_state_dir() {
    if [ ! -d "$STATE_DIR" ]; then
        mkdir -p "$STATE_DIR"
        log_info "Created state directory: $STATE_DIR"
    fi
}

# Save to state
state_save() {
    local key="$1"
    local value="$2"
    
    create_state_dir
    echo "${key}: ${value}" >> "$STATE_DIR/state.yaml"
}

# Get from state
state_get() {
    local key="$1"
    
    if [ ! -f "$STATE_DIR/state.yaml" ]; then
        return 1
    fi
    
    grep "^${key}:" "$STATE_DIR/state.yaml" | awk '{print $2}'
}

# Clear state
state_clear() {
    if [ -d "$STATE_DIR" ]; then
        rm -rf "$STATE_DIR"
        log_info "Cleared state directory"
    fi
}

# Check if deployment exists
deployment_exists() {
    [ -f "$STATE_DIR/state.yaml" ]
}

# Show help
show_help() {
    echo -e "${GREEN}TFGrid Compose${NC} - Universal deployment orchestrator for ThreeFold Grid"
    echo ""
    echo -e "${CYAN}Usage:${NC}"
    echo "  tfgrid-compose <command> [options]"
    echo ""
    echo -e "${CYAN}Commands:${NC}"
    echo -e "  ${GREEN}init${NC} <app>            Initialize app configuration (interactive)"
    echo -e "  ${GREEN}up${NC} <app>              Deploy an application"
    echo -e "  ${GREEN}down${NC} <app>            Destroy a deployment"
    echo -e "  ${GREEN}exec${NC} <app> <cmd>      Execute command on deployed VM"
    echo -e "  ${GREEN}clean${NC}                 Clean up local state directory"
    echo -e "  ${GREEN}logs${NC} <app>            Show application logs"
    echo -e "  ${GREEN}status${NC} <app>          Check application status"
    echo -e "  ${GREEN}ssh${NC} <app>             SSH into the deployment"
    echo -e "  ${GREEN}address${NC} <app>         Show deployment addresses"
    echo -e "  ${GREEN}patterns${NC}              List available deployment patterns"
    echo -e "  ${GREEN}help${NC}                  Show this help message"
    echo ""
    echo -e "${CYAN}Quick Start:${NC}"
    echo "  1. Initialize: tfgrid-compose init tfgrid-ai-agent"
    echo "  2. Set secrets:  set -x TF_VAR_mnemonic (cat ~/.config/threefold/mnemonic)"
    echo "  3. Deploy:       tfgrid-compose up tfgrid-ai-agent"
    echo "  4. Use it:       tfgrid-compose exec tfgrid-ai-agent <command>"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  tfgrid-compose init tfgrid-ai-agent"
    echo "  tfgrid-compose up tfgrid-ai-agent"
    echo "  tfgrid-compose exec tfgrid-ai-agent login"
    echo "  tfgrid-compose exec tfgrid-ai-agent create my-project"
    echo "  tfgrid-compose exec tfgrid-ai-agent run my-project"
    echo "  tfgrid-compose logs tfgrid-ai-agent"
    echo "  tfgrid-compose ssh tfgrid-ai-agent"
    echo "  tfgrid-compose down tfgrid-ai-agent"
    echo ""
    echo -e "${CYAN}Documentation:${NC}"
    echo "  https://github.com/tfgrid-studio/tfgrid-compose"
    echo ""
    echo -e "${CYAN}Version:${NC} 0.9.0"
}

# Export functions for use in other scripts
export -f log_info
export -f log_success
export -f log_warning
export -f log_error
export -f log_step
export -f command_exists
export -f validate_directory
export -f validate_file
export -f yaml_get
export -f state_save
export -f state_get
export -f state_clear
export -f deployment_exists
