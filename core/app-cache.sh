#!/usr/bin/env bash
# TFGrid Compose - Enhanced App Cache Module
# Handles downloading, caching, and Git-based version tracking app repositories

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

# Get registry version for an app
get_registry_version() {
    local app_name="$1"

    local registry=$(get_registry 2>/dev/null)
    if [ -z "$registry" ]; then
        echo "unknown"
        return 1
    fi

    # Extract version from registry (supports nested apps.official/apps.verified format)
    echo "$registry" | awk -v app="$app_name" '
    /^  - name:/ {
        current_app = $3
        gsub(/^[ \t]+|[ \t]+$/, "", current_app)
        if (current_app == app) {
            in_app = 1
        } else {
            in_app = 0
        }
    }

    in_app && /^    version:/ {
        version = substr($0, index($0, "version:") + 8)
        gsub(/^[ \t]+|[ \t]+$/, "", version)
        print version
        exit
    }'
}

# Check if cached app needs update (Git-based with registry version checking)
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

    # Get cached metadata
    local metadata=$(get_cache_metadata "$app_name")
    local cached_commit=$(echo "$metadata" | jq -r '.commit_hash // "unknown"')

    # Migration check: If old cache format (has cache_version but no commit_hash)
    local has_cache_version=$(echo "$metadata" | jq -r '.cache_version // empty' | grep -v '^empty' | wc -l)
    local has_commit_hash=$(echo "$metadata" | jq -r '.commit_hash // empty' | grep -v '^unknown' | grep -v '^empty' | wc -l)

    # If has cache_version but no commit_hash, needs migration to Git-based
    if [ "$has_cache_version" -gt 0 ] && [ "$has_commit_hash" -eq 0 ]; then
        log_info "Migrating $app_name from cache_version to Git-based tracking..."
        return 0
    fi

    # NEW: Check if registry version differs from cached commit
    local registry_version=$(get_registry_version "$app_name")
    if [ "$registry_version" != "unknown" ] && [ "$registry_version" != "$cached_commit" ]; then
        log_info "Registry version ($registry_version) differs from cached ($cached_commit) - update needed"
        return 0
    fi

    # Get current commit hash
    cd "$app_dir"
    local current_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    cd - >/dev/null

    # If commit hashes differ, update needed
    if [ "$cached_commit" != "$current_commit" ] || [ "$cached_commit" = "unknown" ]; then
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

# Validate cached app integrity with enhanced error reporting
validate_cached_app() {
    local app_name="$1"
    local app_dir="$APPS_CACHE_DIR/$app_name"
    local issues=()
    local syntax_errors=()
    
    # Check required files exist
    [ -f "$app_dir/tfgrid-compose.yaml" ] || issues+=("Missing manifest file")
    [ -d "$app_dir/.git" ] || issues+=("Missing git repository")
    
    # Check deployment hooks
    if [ -d "$app_dir/deployment" ]; then
        [ -f "$app_dir/deployment/setup.sh" ] || issues+=("Missing setup hook")
        [ -f "$app_dir/deployment/configure.sh" ] || issues+=("Missing configure hook")
        [ -f "$app_dir/deployment/healthcheck.sh" ] || issues+=("Missing healthcheck hook")
        
        # Enhanced syntax validation for shell scripts
        for hook in setup.sh configure.sh healthcheck.sh; do
            if [ -f "$app_dir/deployment/$hook" ]; then
                # Run syntax check and capture detailed output
                local syntax_output
                syntax_output=$(bash -n "$app_dir/deployment/$hook" 2>&1)
                local syntax_exit_code=$?
                
                if [ $syntax_exit_code -ne 0 ]; then
                    # Parse syntax error to get line number and message
                    local error_line=$(echo "$syntax_output" | grep -o 'line [0-9]*' | grep -o '[0-9]*' | head -1)
                    local error_message=$(echo "$syntax_output" | grep -v '^line [0-9]*' | head -1)
                    
                    if [ -n "$error_line" ] && [ -n "$error_message" ]; then
                        syntax_errors+=("$hook: line $error_line - $error_message")
                    else
                        syntax_errors+=("$hook: $syntax_output")
                    fi
                    issues+=("Syntax error in $hook")
                fi
            fi
        done
    else
        issues+=("Missing deployment directory")
    fi
    
    # Check manifest syntax
    if [ -f "$app_dir/tfgrid-compose.yaml" ]; then
        # Enhanced YAML validation with error details
        local yaml_output
        yaml_output=$(python3 -c "import yaml; yaml.safe_load(open('$app_dir/tfgrid-compose.yaml'))" 2>&1)
        if [ $? -ne 0 ]; then
            issues+=("Invalid YAML in manifest")
            # Show first line of YAML error for debugging
            local first_error=$(echo "$yaml_output" | head -1)
            if [ -n "$first_error" ]; then
                log_debug "YAML error details: $first_error"
            fi
        fi
    fi
    
    # Return issues
    if [ ${#issues[@]} -eq 0 ]; then
        return 0
    else
        log_warning "Cache validation issues for $app_name:"
        for issue in "${issues[@]}"; do
            log_warning "  - $issue"
        done
        
        # Show detailed syntax errors if any
        if [ ${#syntax_errors[@]} -gt 0 ]; then
            log_info "Detailed syntax errors:"
            for error in "${syntax_errors[@]}"; do
                log_info "  💥 $error"
            done
            log_info ""
            log_info "🔧 To fix: Clear cache and re-download fresh version"
            log_info "   Run: t cache clear $app_name && t update $app_name"
        fi
        
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

# Clone app repository to cache with Git-based version tracking and migration support
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

    # Get registry version (commit hash) to check out specific version
    local registry_version=$(get_registry_version "$app_name")

    # Clone repository with better error handling
    local clone_output
    local clone_exit_code

    # Handle existing directory gracefully
    if [ -d "$app_dir" ]; then
        if [ -d "$app_dir/.git" ]; then
            # Directory exists with git repository - update existing
            log_info "Updating existing cached app: $app_name"
            cd "$app_dir"
            if git pull --quiet origin main 2>/dev/null || git pull --quiet origin master 2>/dev/null; then
                clone_exit_code=0
                clone_output="Updated existing repository"
            else
                clone_exit_code=1
                clone_output="Failed to update existing repository"
            fi
            cd - >/dev/null
        else
            # Directory exists but no git repository - remove and clone fresh
            log_info "Removing corrupted cache directory: $app_name"
            rm -rf "$app_dir"
            clone_output=$(git clone "$repo_url" "$app_dir" 2>&1)
            clone_exit_code=$?
        fi
    else
        # Directory doesn't exist - clone fresh
        clone_output=$(git clone "$repo_url" "$app_dir" 2>&1)
        clone_exit_code=$?
    fi

    if [ $clone_exit_code -eq 0 ]; then
        # Check out specific registry version if available
        if [ "$registry_version" != "unknown" ] && [ -n "$registry_version" ]; then
            cd "$app_dir"
            if git checkout --quiet "$registry_version" 2>/dev/null; then
                log_info "Checked out registry version $registry_version for $app_name"
                local commit_hash="$registry_version"
            else
                log_warning "Failed to checkout registry version $registry_version, using HEAD"
                local commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
            fi
            cd - >/dev/null
        else
            # Get current Git commit hash
            cd "$app_dir"
            local commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
            cd - >/dev/null
        fi

        local manifest_version=$(yaml_get "$app_dir/tfgrid-compose.yaml" "version" 2>/dev/null || echo "unknown")

        # Validate that we got valid data
        if [ "$commit_hash" = "unknown" ] || [ "$manifest_version" = "unknown" ]; then
            log_warning "Invalid repository data for $app_name, removing cache"
            rm -rf "$app_dir"
            log_error "Failed to get valid repository data from $repo_url"
            return 1
        fi

        # Check if migrating from old cache_version format
        local old_metadata=$(get_cache_metadata "$app_name")
        local has_cache_version=$(echo "$old_metadata" | jq -r '.cache_version // empty' | grep -v '^empty' | wc -l)

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

        # Store registry version for future reference
        if [ "$registry_version" != "unknown" ]; then
            metadata=$(echo "$metadata" | jq ".registry_version = \"$registry_version\"")
        fi

        # Remove old cache_version from metadata if it exists
        if [ "$has_cache_version" -gt 0 ]; then
            log_info "Migrating $app_name from cache_version to Git-based tracking"
            metadata=$(echo "$metadata" | jq 'del(.cache_version)')
        fi

        set_cache_metadata "$app_name" "$metadata"

        # Provide appropriate success message based on whether it was update or fresh clone
        if echo "$clone_output" | grep -q "Updated existing repository"; then
            log_success "Updated $app_name to registry version"
        else
            log_success "Downloaded $app_name"
        fi
        return 0
    else
        # Only remove directory if it didn't exist before (fresh clone failure)
        if [ ! -d "$app_dir" ]; then
            rm -rf "$app_dir"
        fi

        # Check for specific error types and provide helpful messages
        if echo "$clone_output" | grep -q "rate limit"; then
            log_error "GitHub rate limiting detected for $app_name"
            log_info "This usually means too many requests were made to GitHub"
            log_info "Wait a few minutes and try again"
        elif echo "$clone_output" | grep -q "Repository not found"; then
            log_error "Repository not found: $repo_url"
            log_info "Check if the repository exists and is accessible"
        elif echo "$clone_output" | grep -q "Authentication failed"; then
            log_error "Authentication failed for $repo_url"
            log_info "Repository may be private or require authentication"
        elif echo "$clone_output" | grep -q "Could not resolve host"; then
            log_error "Network connectivity issue for $repo_url"
            log_info "Check your internet connection and DNS settings"
        else
            log_error "Failed to update $app_name from $repo_url"
            log_info "Error details: $clone_output"
            if [ -d "$app_dir/.git" ]; then
                log_info "Keeping existing cached version due to update failure"
            fi
        fi
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
        # Get registry version to check out if available
        local registry_version=$(get_registry_version "$app_name")

        # Check out registry version if available
        local commit_hash
        if [ "$registry_version" != "unknown" ] && [ -n "$registry_version" ]; then
            if git checkout --quiet "$registry_version" 2>/dev/null; then
                log_info "Checked out registry version $registry_version for $app_name"
                commit_hash="$registry_version"
            else
                log_warning "Failed to checkout registry version $registry_version, using HEAD"
                commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
            fi
        else
            commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        fi

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

        # Store registry version for future reference
        if [ "$registry_version" != "unknown" ]; then
            metadata=$(echo "$metadata" | jq ".registry_version = \"$registry_version\"")
        fi

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

# Get or download app with smart cache management and registry support
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
    
    # If no repo_url provided, try to get it from registry
    if [ -z "$repo_url" ]; then
        repo_url=$(get_app_repo "$app_name" 2>/dev/null)
        if [ -z "$repo_url" ]; then
            log_error "App '$app_name' is not cached and not found in registry"
            return 1
        fi
        log_info "Downloading $app_name from registry..."
    fi
    
    # Download app
    if cache_app "$app_name" "$repo_url"; then
        echo "$app_dir"
        return 0
    else
        return 1
    fi
}

# Enhanced list cached apps with status and commit information
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
            
            # Get commit hash for display
            local git_info=$(get_cached_app_git_info "$app_name" 2>/dev/null)
            local short_commit=$(echo "$git_info" | jq -r '.short_commit // "unknown"')
            local formatted_date=$(echo "$git_info" | jq -r '.formatted_date // "unknown"')
            
            if [ "$short_commit" != "unknown" ]; then
                echo "$icon $app_name ($short_commit)$update_flag"
                if [ "$formatted_date" != "unknown" ]; then
                    echo "    Last updated: $formatted_date"
                fi
            else
                echo "$icon $app_name$update_flag"
            fi
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

# Get Git information from cached app
get_cached_app_git_info() {
    local app_name="$1"
    local app_dir="$APPS_CACHE_DIR/$app_name"
    
    if [ ! -d "$app_dir/.git" ]; then
        echo "{}"
        return 1
    fi
    
    cd "$app_dir"
    
    # Get Git information
    local commit_hash=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    local short_commit=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")
    local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    local commit_date=$(git log -1 --format=%ct 2>/dev/null || echo "0")
    local commit_message=$(git log -1 --format=%s 2>/dev/null || echo "unknown")
    local repo_url=$(git config --get remote.origin.url 2>/dev/null || echo "unknown")
    
    cd - >/dev/null
    
    # Format date
    local formatted_date=""
    if [ "$commit_date" != "0" ] && [ "$commit_date" != "unknown" ]; then
        formatted_date=$(date -d "@$commit_date" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
    fi
    
    cat << EOF | jq -c '.'
{
  "commit_hash": "$commit_hash",
  "short_commit": "$short_commit", 
  "branch": "$branch",
  "commit_date": "$commit_date",
  "formatted_date": "$formatted_date",
  "commit_message": "$commit_message",
  "repo_url": "$repo_url"
}
EOF
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

# Export new functions
export -f get_registry_app_cache_version
export -f get_app_cache_version
export -f cache_needs_update
export -f get_cached_app_git_info
