#!/usr/bin/env bash
# App loader - Loads and validates application manifests

# Load common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# App variables (will be populated by load_app)
APP_NAME=""
APP_VERSION=""
APP_DESCRIPTION=""
APP_DIR=""
APP_MANIFEST=""
APP_RECOMMENDED_PATTERN=""
APP_DEPLOYMENT_DIR=""
APP_SRC_DIR=""

# Load app manifest
load_app() {
    local app_path="$1"
    
    if [ -z "$app_path" ]; then
        log_error "App path is required"
        return 1
    fi
    
    log_step "Loading application: $app_path"
    
    # Check if app is cached and use cached version
    if is_app_cached "$app_path"; then
        APP_DIR=$(get_cached_app_path "$app_path")
        APP_PATH="$APP_DIR"  # Also update APP_PATH for consistency
        log_info "Using cached app: $app_path"
    else
        # Handle relative vs absolute paths
        if [[ "$app_path" = /* ]]; then
            APP_DIR="$app_path"
        else
            APP_DIR="$(pwd)/$app_path"
        fi
    fi
    
    if ! validate_directory "$APP_DIR" "Application"; then
        log_error "Application not found: $app_path"
        return 1
    fi
    
    # Resolve manifest path (use custom file if specified)
    local manifest_file="${APP_MANIFEST_FILE:-tfgrid-compose.yaml}"
    APP_MANIFEST="$APP_DIR/$manifest_file"
    if [ ! -f "$APP_MANIFEST" ]; then
        APP_MANIFEST="$APP_DIR/tfgrid-compose.yml"
    fi
    
    # Validate manifest exists
    if ! validate_file "$APP_MANIFEST" "Application manifest"; then
        log_error "No tfgrid-compose.yaml found in: $app_path"
        return 1
    fi
    
    # Load app metadata
    log_info "Reading application manifest..."
    
    APP_NAME=$(yaml_get "$APP_MANIFEST" "name")
    APP_VERSION=$(yaml_get "$APP_MANIFEST" "version")
    APP_DESCRIPTION=$(yaml_get "$APP_MANIFEST" "description")
    APP_RECOMMENDED_PATTERN=$(yaml_get "$APP_MANIFEST" "patterns.recommended")
    
    if [ -z "$APP_NAME" ]; then
        log_error "Invalid manifest: missing 'name' field"
        return 1
    fi
    
    # Set app directories
    APP_DEPLOYMENT_DIR="$APP_DIR/deployment"
    APP_SRC_DIR="$APP_DIR/src"
    
    # Log app info with enhanced version information
    log_success "Application loaded: $APP_NAME v$APP_VERSION"
    
    # Show Git commit information if app is cached
    if is_app_cached "$APP_NAME"; then
        local git_info=$(get_cached_app_git_info "$APP_NAME" 2>/dev/null)
        if [ -n "$git_info" ] && [ "$git_info" != "{}" ]; then
            local short_commit=$(echo "$git_info" | jq -r '.short_commit // "unknown"')
            local formatted_date=$(echo "$git_info" | jq -r '.formatted_date // "unknown"')
            local branch=$(echo "$git_info" | jq -r '.branch // "unknown"')
            local repo_url=$(echo "$git_info" | jq -r '.repo_url // "unknown"')
            
            if [ "$short_commit" != "unknown" ]; then
                log_info "Git commit: $short_commit"
            fi
            if [ "$formatted_date" != "unknown" ]; then
                log_info "Last updated: $formatted_date"
            fi
            if [ "$branch" != "unknown" ]; then
                log_info "Branch: $branch"
            fi
            if [ "$repo_url" != "unknown" ]; then
                log_info "Repository: $repo_url"
            fi
        fi
    fi
    
    log_info "Description: $APP_DESCRIPTION"
    
    if [ -n "$APP_RECOMMENDED_PATTERN" ]; then
        log_info "Recommended pattern: $APP_RECOMMENDED_PATTERN"
    fi
    
    return 0
}

# Get app resource requirements
get_app_resource() {
    local resource="$1"
    local type="$2"  # min, recommended, max
    
    if [ -z "$type" ]; then
        type="recommended"
    fi
    
    yaml_get "$APP_MANIFEST" "resources.${resource}.${type}"
}

# Get app dependencies
get_app_dependencies() {
    local dep_type="$1"  # system, external
    
    if [ ! -f "$APP_MANIFEST" ]; then
        return 1
    fi
    
    # Basic extraction (would need better YAML parser for arrays)
    grep -A 10 "dependencies:" "$APP_MANIFEST" | grep -A 5 "${dep_type}:" | grep "^[[:space:]]*-" | sed 's/^[[:space:]]*-[[:space:]]*//'
}

# Validate app hooks exist
validate_app_hooks() {
    log_step "Validating application hooks..."
    
    # Check deployment directory
    if [ ! -d "$APP_DEPLOYMENT_DIR" ]; then
        log_error "Deployment directory not found: $APP_DEPLOYMENT_DIR"
        return 1
    fi
    
    # Required hooks
    local required_hooks=("setup.sh" "configure.sh" "healthcheck.sh")
    
    for hook in "${required_hooks[@]}"; do
        local hook_path="$APP_DEPLOYMENT_DIR/$hook"
        
        if [ ! -f "$hook_path" ]; then
            log_error "Required hook missing: $hook"
            return 1
        fi
        
        if [ ! -x "$hook_path" ]; then
            log_warning "Hook is not executable: $hook (fixing...)"
            chmod +x "$hook_path"
        fi
        
        log_success "Hook found: $hook"
    done
    
    return 0
}

# Execute app hook
execute_app_hook() {
    local hook_name="$1"
    shift
    
    local hook_path="$APP_DEPLOYMENT_DIR/${hook_name}.sh"
    
    if ! validate_file "$hook_path" "App hook"; then
        return 1
    fi
    
    if [ ! -x "$hook_path" ]; then
        log_error "Hook is not executable: $hook_path"
        return 1
    fi
    
    log_step "Executing app hook: $hook_name"
    
    # Execute the hook
    bash "$hook_path" "$@"
    return $?
}

# Check pattern compatibility
check_pattern_compatibility() {
    local pattern_name="$1"
    
    if [ -z "$pattern_name" ]; then
        log_error "Pattern name is required"
        return 1
    fi
    
    log_step "Checking pattern compatibility..."
    
    # Get supported patterns from manifest
    local supported=$(grep -A 10 "patterns:" "$APP_MANIFEST" | grep -A 5 "supported:" | grep "^[[:space:]]*-" | sed 's/^[[:space:]]*-[[:space:]]*//')
    
    # Check if pattern is in supported list
    if echo "$supported" | grep -q "^${pattern_name}$"; then
        log_success "Pattern '$pattern_name' is supported"
        return 0
    else
        log_error "Pattern '$pattern_name' is NOT supported by this app"
        log_info "Supported patterns:"
        echo "$supported" | sed 's/^/  /'
        return 1
    fi
}

# Get recommended pattern
get_recommended_pattern() {
    if [ -z "$APP_RECOMMENDED_PATTERN" ]; then
        yaml_get "$APP_MANIFEST" "patterns.recommended"
    else
        echo "$APP_RECOMMENDED_PATTERN"
    fi
}

# Validate app structure
validate_app_structure() {
    log_step "Validating application structure..."
    
    # Check manifest
    if ! validate_file "$APP_MANIFEST" "Manifest"; then
        return 1
    fi
    log_success "Manifest found"
    
    # Check deployment hooks
    if ! validate_app_hooks; then
        return 1
    fi
    
    # Check source directory (optional but recommended)
    if [ -d "$APP_SRC_DIR" ]; then
        log_success "Source directory found"
    else
        log_warning "No source directory found (optional)"
    fi
    
    log_success "Application structure is valid"
    return 0
}

# Get app environment variables
get_app_environment() {
    if [ ! -f "$APP_MANIFEST" ]; then
        return 1
    fi
    
    # Extract environment variables (basic implementation)
    grep -A 50 "environment:" "$APP_MANIFEST" | grep "^[[:space:]]*-[[:space:]]name:" | sed 's/^.*name:[[:space:]]*//'
}

# Export app variables for use in other scripts
export APP_NAME
export APP_VERSION
export APP_DESCRIPTION
export APP_DIR
export APP_MANIFEST
export APP_RECOMMENDED_PATTERN
export APP_DEPLOYMENT_DIR
export APP_SRC_DIR

# Export functions
export -f load_app
export -f get_app_resource
export -f get_app_dependencies
export -f validate_app_hooks
export -f execute_app_hook
export -f check_pattern_compatibility
export -f get_recommended_pattern
export -f validate_app_structure
export -f get_app_environment
