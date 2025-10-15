#!/usr/bin/env bash
# TFGrid Compose - App Cache Module
# Handles downloading and caching app repositories locally

# Cache configuration
APPS_CACHE_DIR="$HOME/.config/tfgrid-compose/apps"

# Ensure cache directory exists
ensure_cache_dir() {
    mkdir -p "$APPS_CACHE_DIR"
}

# Check if app is cached
is_app_cached() {
    local app_name="$1"
    local app_dir="$APPS_CACHE_DIR/$app_name"
    
    [ -d "$app_dir/.git" ]
}

# Get cached app path
get_cached_app_path() {
    local app_name="$1"
    echo "$APPS_CACHE_DIR/$app_name"
}

# Clone app repository to cache
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
        log_success "Downloaded $app_name"
        return 0
    else
        rm -rf "$app_dir"
        log_error "Failed to download $app_name from $repo_url"
        return 1
    fi
}

# Update cached app
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
        log_success "Updated $app_name"
        cd - >/dev/null
        return 0
    else
        log_warning "Failed to update $app_name (using cached version)"
        cd - >/dev/null
        return 1
    fi
}

# Get or download app
get_app() {
    local app_name="$1"
    local repo_url="$2"
    local app_dir="$APPS_CACHE_DIR/$app_name"
    
    # If cached, optionally update
    if is_app_cached "$app_name"; then
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

# List cached apps
list_cached_apps() {
    ensure_cache_dir
    
    if [ ! "$(ls -A $APPS_CACHE_DIR 2>/dev/null)" ]; then
        return 0
    fi
    
    for app_dir in "$APPS_CACHE_DIR"/*; do
        if [ -d "$app_dir/.git" ]; then
            basename "$app_dir"
        fi
    done
}

# Clean app cache
clean_app_cache() {
    local app_name="$1"
    
    if [ -z "$app_name" ]; then
        # Clean all
        log_info "Cleaning app cache..."
        rm -rf "$APPS_CACHE_DIR"
        log_success "App cache cleaned"
    else
        # Clean specific app
        local app_dir="$APPS_CACHE_DIR/$app_name"
        if [ -d "$app_dir" ]; then
            log_info "Removing cached app: $app_name"
            rm -rf "$app_dir"
            log_success "Removed $app_name from cache"
        else
            log_warning "App $app_name is not cached"
        fi
    fi
}
