#!/usr/bin/env bash
# Pattern loader - Loads and validates deployment patterns

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Pattern variables (will be populated by load_pattern)
PATTERN_NAME=""
PATTERN_VERSION=""
PATTERN_DESCRIPTION=""
PATTERN_DIR=""
PATTERN_INFRASTRUCTURE_DIR=""
PATTERN_PLATFORM_DIR=""
PATTERN_SCRIPTS_DIR=""

# Load pattern metadata
load_pattern() {
    local pattern_name="$1"
    
    if [ -z "$pattern_name" ]; then
        log_error "Pattern name is required"
        return 1
    fi
    
    log_step "Loading pattern: $pattern_name"
    
    # Get deployer root
    local deployer_root="$(get_deployer_root)"
    PATTERN_DIR="$deployer_root/patterns/$pattern_name"
    
    # Validate pattern directory exists
    if ! validate_directory "$PATTERN_DIR" "Pattern"; then
        log_error "Pattern not found: $pattern_name"
        log_info "Available patterns:"
        ls -1 "$deployer_root/patterns/" 2>/dev/null || echo "  (none)"
        return 1
    fi
    
    # Validate pattern.yaml exists
    local pattern_file="$PATTERN_DIR/pattern.yaml"
    if ! validate_file "$pattern_file" "Pattern metadata"; then
        return 1
    fi
    
    # Load pattern metadata
    log_info "Reading pattern metadata..."
    
    PATTERN_NAME=$(yaml_get "$pattern_file" "name")
    PATTERN_VERSION=$(yaml_get "$pattern_file" "version")
    PATTERN_DESCRIPTION=$(yaml_get "$pattern_file" "description")
    
    if [ -z "$PATTERN_NAME" ]; then
        log_error "Invalid pattern.yaml: missing 'name' field"
        return 1
    fi
    
    # Set pattern directories
    PATTERN_INFRASTRUCTURE_DIR="$PATTERN_DIR/infrastructure"
    PATTERN_PLATFORM_DIR="$PATTERN_DIR/platform"
    PATTERN_SCRIPTS_DIR="$PATTERN_DIR/scripts"
    
    # Validate required directories
    if ! validate_directory "$PATTERN_INFRASTRUCTURE_DIR" "Pattern infrastructure"; then
        return 1
    fi
    
    if ! validate_directory "$PATTERN_PLATFORM_DIR" "Pattern platform"; then
        return 1
    fi
    
    if ! validate_directory "$PATTERN_SCRIPTS_DIR" "Pattern scripts"; then
        return 1
    fi
    
    # Log pattern info
    log_success "Pattern loaded: $PATTERN_NAME v$PATTERN_VERSION"
    log_info "Description: $PATTERN_DESCRIPTION"
    
    return 0
}

# Get pattern commands
get_pattern_commands() {
    local pattern_file="$PATTERN_DIR/pattern.yaml"
    
    if [ ! -f "$pattern_file" ]; then
        return 1
    fi
    
    # List available commands from scripts directory
    if [ -d "$PATTERN_SCRIPTS_DIR" ]; then
        ls -1 "$PATTERN_SCRIPTS_DIR"/*.sh 2>/dev/null | xargs -n 1 basename | sed 's/\.sh$//'
    fi
}

# Execute pattern script
execute_pattern_script() {
    local script_name="$1"
    shift
    
    local script_path="$PATTERN_SCRIPTS_DIR/${script_name}.sh"
    
    if ! validate_file "$script_path" "Pattern script"; then
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        log_error "Script is not executable: $script_path"
        return 1
    fi
    
    log_step "Executing pattern script: $script_name"
    
    # Execute the script
    bash "$script_path" "$@"
    return $?
}

# Get pattern resource defaults
get_pattern_defaults() {
    local pattern_file="$PATTERN_DIR/pattern.yaml"
    local key="$1"
    
    if [ ! -f "$pattern_file" ]; then
        return 1
    fi
    
    yaml_get "$pattern_file" "defaults.$key"
}

# Validate pattern requirements
validate_pattern_requirements() {
    local pattern_file="$PATTERN_DIR/pattern.yaml"
    
    if [ ! -f "$pattern_file" ]; then
        return 1
    fi
    
    log_step "Validating pattern requirements..."
    
    # Check if Terraform is required
    if [ -d "$PATTERN_INFRASTRUCTURE_DIR" ] && [ -n "$(ls -A "$PATTERN_INFRASTRUCTURE_DIR"/*.tf 2>/dev/null)" ]; then
        if ! command_exists terraform; then
            log_error "Terraform is required for this pattern"
            return 1
        fi
        log_success "Terraform available"
    fi
    
    # Check if Ansible is required
    if [ -d "$PATTERN_PLATFORM_DIR" ] && [ -f "$PATTERN_PLATFORM_DIR/site.yml" ]; then
        if ! command_exists ansible-playbook; then
            log_error "Ansible is required for this pattern"
            return 1
        fi
        log_success "Ansible available"
    fi
    
    return 0
}

# List available patterns
list_patterns() {
    local deployer_root="$(get_deployer_root)"
    local patterns_dir="$deployer_root/patterns"
    
    if [ ! -d "$patterns_dir" ]; then
        log_error "No patterns directory found"
        return 1
    fi
    
    log_info "Available patterns:"
    echo ""
    
    for pattern_dir in "$patterns_dir"/*; do
        if [ -d "$pattern_dir" ]; then
            local pattern=$(basename "$pattern_dir")
            local pattern_file="$pattern_dir/pattern.yaml"
            
            if [ -f "$pattern_file" ]; then
                local version=$(yaml_get "$pattern_file" "version")
                local description=$(yaml_get "$pattern_file" "description")
                
                echo -e "  ${GREEN}$pattern${NC} (v$version)"
                echo -e "    $description"
                echo ""
            fi
        fi
    done
}

# Export pattern variables for use in other scripts
export PATTERN_NAME
export PATTERN_VERSION
export PATTERN_DESCRIPTION
export PATTERN_DIR
export PATTERN_INFRASTRUCTURE_DIR
export PATTERN_PLATFORM_DIR
export PATTERN_SCRIPTS_DIR

# Export functions
export -f load_pattern
export -f get_pattern_commands
export -f execute_pattern_script
export -f get_pattern_defaults
export -f validate_pattern_requirements
export -f list_patterns
