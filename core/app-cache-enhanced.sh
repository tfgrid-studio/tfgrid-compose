#!/usr/bin/env bash
# TFGrid Compose - Enhanced App Cache Module
# Handles downloading, caching, and version tracking app repositories

# Cache configuration
APPS_CACHE_DIR="$HOME/.config/tfgrid-compose/apps"
CACHE_METADATA_DIR="$HOME/.config/tfgrid-compose/cache-metadata"

# Ensure cache directories exist
ensure_cache_dir() {
    mkdir -p "$APPS_CACHE_DIR"
    mkdir -p "$CACHE_METADATA_DIR"
}

# Cache version tracking file
get_cache_metadata_file() {
    local app_name="$1"
    echo "$CACHE_METADATA_DIR/$app_name.json"
}

# Check if app is cached
is_app_cached() {
    local app_name="$1"
    local app_dir="$APPS_CACHE_DIR/$app_name"
    
    [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]
}

# Get cached app path
get_cached_app_path() {
    local app_name="$1"
    echo "$APPS_CACHE_DIR/$app_name"
}

# Get app metadata
get_cache_metadata() {
    local app_name="$1"
    local metadata_file=$(get_cache_metadata_file "$app_name")
    
    if [ -f "$metadata_file" ]; then
        cat "$metadata_file"
    else
        echo "{}"
    fi
}

# Set app metadata
set_cache_metadata() {
    local app_name="$1"
    local metadata="$2"
    local metadata_file=$(get_cache_metadata_file "$app_name")
    
    echo "$metadata" > "$metadata_file"
}

# Check if cached app needs update (Git-based)
cache_needs_update() {
    local app_name="$1"
    local app_dir="$APPS_CACHE_DIR/$app_name"
    local metadata_file=$(get_cache_metadata_file "$app_name")
    
    # If no metadata, needs update
    if [ ! -f "$metadata_file" ]; then
        return 0
    fi
    
    # If app not cached, needs update
    if [ ! -d "$app_dir/.git" ]; then
        return 0
    fi
    
    # Get cached commit hash
    local cached_commit=$(get_cache_metadata "$app_name" | jq -r '.commit_hash // "unknown"')
    
    # Get current commit hash
    cd "$app_dir"
    local current_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    cd - >/dev/null
    
    # If commit hashes differ, update needed
    if [ "$cached_commit" != "$current_commit" ]; then
        return 0
    fi
    
    # Check if cache is stale (older than 24 hours) - optional fallback
    local cache_age=$(( $(date +%s) - $(stat -c %Y "$metadata_file" 2>/dev/null || stat -f %m "$metadata_file" 2>/dev/null || echo 0) ))
    local max_age=86400  # 24 hours
    
    if [ $cache_age -gt $max_age ]; then
        return 0
    fi
    
    return 1
}

# Validate cached app integrity
validate_cached_app() {
    local app_name="$1"
    local app_dir="$APPS_CACHE_DIR/$app_name"
    local issues=()
    
    # Check required files exist
    [ -f "$app_dir/tfgrid-compose.yaml" ] || issues+=("Missing manifest file")
    [ -d "$app_dir/.git" ] || issues+=("Missing git repository")
    
    # Check deployment hooks
    if [ -d "$app_dir/deployment" ]; then
        [ -f "$app_dir/deployment/setup.sh" ] || issues+=("Missing setup hook")
        [ -f "$app_dir/deployment/configure.sh" ] || issues+=("Missing configure hook")
        [ -f "$app_dir/deployment/healthcheck.sh" ] || issues+=("Missing healthcheck hook")
        
        # Syntax validation for shell scripts
        for hook in setup.sh configure.sh healthcheck.sh; do
            if [ -f "$app_dir/deployment/$hook" ]; then
                bash -n "$app_dir/deployment/$hook" || issues+=("Syntax error in $hook")
            fi
        done
    else
        issues+=("Missing deployment directory")
    fi
    
    # Check manifest syntax
    if [ -f "$app_dir/tfgrid-compose.yaml" ]; then
        # Basic YAML validation
        python3 -c "import yaml; yaml.safe_load(open('$app_dir/tfgrid-compose.yaml'))" 2>/dev/null || issues+=("Invalid YAML in manifest")
    fi
    
    # Return issues
    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    else
        log_warning "Cache validation issues for $app_name:"
        for issue in "${issues[@]}"; do
            log_warning "  - $issue"
        done
        return 1
    fi
}

# Get cache health status
get_cache_health() {
    local app_name="$1"
    local status="unknown"
    local issues=()
    
    if ! is_app_cached "$app_name"; then
        status="not_cached"
    elif ! validate_cached_app "$app_name"; then
        status="invalid"
        issues+=("validation_failed")
    elif cache_needs_update "$app_name"; then
        status="stale"
    else
        status="healthy"
    fi
    
    # Create JSON status
    local metadata=$(get_cache_metadata "$app_name")
    local updated_at=$(stat -c %Y "$(get_cache_metadata_file "$app_name")" 2>/dev/null || echo "0")
    
    cat << EOF | jq -c '.'
{
  "app_name": "$app_name",
  "status": "$status",
  "issues": $(printf '%s\n' "${issues[@]}" | jq -R . | jq -s .),
  "cached": $(is_app_cached "$app_name" && echo "true" || echo "false"),
  "needs_update": $(cache_needs_update "$app_name" && echo "true" || echo "false"),
  "last_updated": $updated_at,
  "metadata": $metadata
}
EOF
}

# Clone app repository to cache with Git-based version tracking
cache_app() {
    local app_name="$1"
    local repo_url="$2"
    local app_dir="$APPS_CACHE_DIR/$app_name"
    
    ensure_cache_dir
    
    log_info "Downloading $app_name..."
    
    # Remove existing if corrupted
    if [ -d "$app_dir" ] && [ ! -d "$app_dir/.git" ]; then
        rm -rf "$app_dir"
    fi
    
    # Clone repository
    if git clone --quiet "$repo_url" "$app_dir" 2>/dev/null; then
        # Get Git commit hash and version info
        cd "$app_dir"
        local commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        local manifest_version=$(yaml_get "$app_dir/tfgrid-compose.yaml" "version" 2>/dev/null || echo "unknown")
        cd - >/dev/null
        
        local metadata=$(cat << EOF | jq -c '.'
{
  "app_name": "$app_name",
  "commit_hash": "$commit_hash",
  "manifest_version": "$manifest_version",
  "repo_url": "$repo_url",
  "cached_at": $(date +%s),
  "last_updated": $(date +%s)
}
EOF
)
        set_cache_metadata "$app_name" "$metadata"
        
        log_success "Downloaded $app_name"
        return 0
    else
        rm -rf "$app_dir"
        log_error "Failed to download $app_name from $repo_url"
        return 1
    fi
}

# Update cached app with Git-based version tracking
update_cached_app() {
    local app_name="$1"
    local app_dir="$APPS_CACHE_DIR/$app_name"
    
    if [ ! -d "$app_dir/.git" ]; then
        log_error "App $app_name is not cached"
        return 1
    fi
    
    log_info "Updating $app_name..."
    
    cd "$app_dir"
    if git pull --quiet origin main 2>/dev/null || git pull --quiet origin master 2>/dev/null; then
        # Get new commit hash and version info
        local commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        local manifest_version=$(yaml_get "$app_dir/tfgrid-compose.yaml" "version" 2>/dev/null || echo "unknown")
        
        local metadata=$(cat << EOF | jq -c '.'
{
  "app_name": "$app_name",
  "commit_hash": "$commit_hash",
  "manifest_version": "$manifest_version",
  "cached_at": $(get_cache_metadata "$app_name" | jq -r '.cached_at // 0'),
  "last_updated": $(date +%s)
}
EOF
)
        set_cache_metadata "$app_name" "$metadata"
        
        log_success "Updated $app_name"
        cd - >/dev/null
        return 0
    else
        log_warning "Failed to update $app_name (using cached version)"
        cd - >/dev/null
        return 1
    fi
}

# Get or download app with smart cache management
get_app() {
    local app_name="$1"
    local repo_url="$2"
    local app_dir="$APPS_CACHE_DIR/$app_name"
    
    # If cached, check if update needed
    if is_app_cached "$app_name"; then
        if cache_needs_update "$app_name"; then
            log_info "Cache for $app_name is stale, updating..."
            if ! update_cached_app "$app_name"; then
                log_warning "Update failed, using cached version"
            fi
        fi
        
        # Validate cache health
        if ! validate_cached_app "$app_name"; then
            log_warning "Cached $app_name has issues, consider refreshing"
        fi
        
        echo "$app_dir"
        return 0
    fi
    
    # Download app
    if cache_app "$app_name" "$repo_url"; then
        echo "$app_dir"
        return 0
    else
        return 1
    fi
}

# Enhanced list cached apps with status
list_cached_apps_enhanced() {
    ensure_cache_dir
    
    if [ ! "$(ls -A $APPS_CACHE_DIR 2>/dev/null)" ]; then
        echo "No cached apps found"
        return 0
    fi
    
    local apps=()
    for app_dir in "$APPS_CACHE_DIR"/*; do
        if [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]; then
            local app_name=$(basename "$app_dir")
            local health=$(get_cache_health "$app_name")
            local status=$(echo "$health" | jq -r '.status')
            
            case "$status" in
                "healthy") icon="✅" ;;
                "stale") icon="🔄" ;;
                "invalid") icon="⚠️" ;;
                "not_cached") icon="❌" ;;
                *) icon="❓" ;;
            esac
            
            local needs_update=$(echo "$health" | jq -r '.needs_update')
            local update_flag=""
            if [ "$needs_update" = "true" ]; then
                update_flag=" [needs update]"
            fi
            
            echo "$icon $app_name$update_flag"
        fi
    done
}

# List apps that need updates (Git-based)
list_outdated_apps() {
    ensure_cache_dir
    
    local found=false
    for app_dir in "$APPS_CACHE_DIR"/*; do
        if [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]; then
            local app_name=$(basename "$app_dir")
            if cache_needs_update "$app_name"; then
                local health=$(get_cache_health "$app_name")
                local cached_commit=$(echo "$health" | jq -r '.metadata.commit_hash // "unknown"')
                
                # Get current commit hash
                cd "$app_dir"
                local current_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
                cd - >/dev/null
                
                echo "📦 $app_name: cache=$cached_commit, latest=$current_commit"
                found=true
            fi
        fi
    done
    
    if [ "$found" = "false" ]; then
        echo "All cached apps are up to date"
    fi
}

# Clean app cache with enhanced options
clean_app_cache() {
    local app_name="$1"
    local force="${2:-false}"
    
    if [ -z "$app_name" ]; then
        # Clean all
        if [ "$force" = "true" ] || [ "$force" = "--force" ]; then
            log_info "Cleaning all app cache..."
            rm -rf "$APPS_CACHE_DIR"
            rm -rf "$CACHE_METADATA_DIR"
            log_success "All app cache cleaned"
        else
            log_warning "This will remove ALL cached apps. Use --force to confirm."
            echo "Run: t cache clear --force"
        fi
    else
        # Clean specific app
        local app_dir="$APPS_CACHE_DIR/$app_name"
        local metadata_file=$(get_cache_metadata_file "$app_name")
        
        if [ -d "$app_dir" ]; then
            log_info "Removing cached app: $app_name"
            rm -rf "$app_dir"
            rm -f "$metadata_file"
            log_success "Removed $app_name from cache"
        else
            log_warning "App $app_name is not cached"
        fi
    fi
}

# Refresh outdated apps automatically
refresh_outdated_apps() {
    log_info "Checking for outdated cached apps..."
    
    local updated_count=0
    local failed_count=0
    
    for app_dir in "$APPS_CACHE_DIR"/*; do
        if [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]; then
            local app_name=$(basename "$app_dir")
            if cache_needs_update "$app_name"; then
                log_info "Refreshing $app_name..."
                if update_cached_app "$app_name"; then
                    ((updated_count++))
                else
                    ((failed_count++))
                fi
            fi
        fi
    done
    
    if [ $updated_count -gt 0 ]; then
        log_success "Updated $updated_count cached apps"
    fi
    
    if [ $failed_count -gt 0 ]; then
        log_warning "Failed to update $failed_count apps"
    fi
    
    if [ $updated_count -eq 0 ] && [ $failed_count -eq 0 ]; then
        log_info "All cached apps are up to date"
    fi
}

# Export functions for use in other scripts
export APPS_CACHE_DIR
export CACHE_METADATA_DIR

export -f is_app_cached
export -f get_cached_app_path
export -f cache_app
export -f update_cached_app
export -f get_app
export -f list_cached_apps_enhanced
export -f list_outdated_apps
export -f clean_app_cache
export -f refresh_outdated_apps
export -f validate_cached_app
export -f get_cache_health

# Get cache version from registry data
get_registry_app_cache_version() {
    local app_name="$1"
    
    local registry=$(get_registry)
    if [ -z "$registry" ]; then
        return 1
    fi
    
    # Extract cache_version directly from registry
    echo "$registry" | awk -v app="$app_name" '
    /^    - name:/ {
        current_app = $3
        gsub(/^[ \t]+|[ \t]+$/, "", current_app)
        if (current_app == app) {
            in_app = 1
        } else {
            in_app = 0
        }
    }
    
    in_app && /^      cache_version:/ {
        version = substr($0, index($0, "cache_version:") + 14)
        gsub(/^[ \t]+|[ \t]+$/, "", version)
        print version
        exit
    }'
}

# Get cache version for specific app from registry
get_app_cache_version() {
    local app_name="$1"
    
    # Try to get from registry metadata first
    local registry_cache_version=$(get_registry_app_cache_version "$app_name" 2>/dev/null || echo "")
    
    if [ -n "$registry_cache_version" ]; then
        echo "$registry_cache_version"
    else
        # Fallback to manifest file
        local app_dir="$APPS_CACHE_DIR/$app_name"
        if [ -f "$app_dir/tfgrid-compose.yaml" ]; then
            yaml_get "$app_dir/tfgrid-compose.yaml" "cache_version" 2>/dev/null || echo "1.0.0"
        else
            echo "1.0.0"
        fi
    fi
}

# Update cached app with Git-based version tracking and registry sync
update_cached_app_with_registry_sync() {
    local app_name="$1"
    local app_dir="$APPS_CACHE_DIR/$app_name"
    
    if [ ! -d "$app_dir/.git" ]; then
        log_error "App $app_name is not cached"
        return 1
    fi
    
    log_info "Updating $app_name with Git-based version tracking..."
    
    cd "$app_dir"
    if git pull --quiet origin main 2>/dev/null || git pull --quiet origin master 2>/dev/null; then
        # Get version information
        local commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        local manifest_version=$(yaml_get "$app_dir/tfgrid-compose.yaml" "version" 2>/dev/null || echo "unknown")
        
        # Update cache metadata with Git-based tracking
        local metadata=$(cat << EOF | jq -c '.'
{
  "app_name": "$app_name",
  "commit_hash": "$commit_hash",
  "manifest_version": "$manifest_version",
  "cached_at": $(get_cache_metadata "$app_name" | jq -r '.cached_at // 0'),
  "last_updated": $(date +%s)
}
EOF
)
        set_cache_metadata "$app_name" "$metadata"
        
        log_success "Updated $app_name to commit $commit_hash"
        cd - >/dev/null
        return 0
    else
        log_warning "Failed to update $app_name (using cached version)"
        cd - >/dev/null
        return 1
    fi
}

# Update registry cache version when manifest is updated
update_registry_cache_version() {
    local app_name="$1"
    local new_version="$2"
    
    # Get current registry cache version
    local current_version=$(get_registry_app_cache_version "$app_name" 2>/dev/null || echo "")
    
    if [ "$current_version" != "$new_version" ]; then
        log_info "Updating registry cache version for $app_name: $current_version → $new_version"
        # This would normally update the registry file, but for now we just log it
        # In production, this could trigger a PR or update mechanism
    fi
}

# Export new functions
export -f get_registry_app_cache_version
export -f get_app_cache_version
export -f update_cached_app_with_registry_sync
export -f update_registry_cache_version
export -f cache_needs_update