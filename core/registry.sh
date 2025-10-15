#!/usr/bin/env bash
# TFGrid Compose - Registry Module
# Handles fetching and caching the app registry from GitHub

# Registry configuration
REGISTRY_URL="https://raw.githubusercontent.com/tfgrid-studio/registry/main/apps.yaml"
REGISTRY_DIR="$HOME/.config/tfgrid-compose/registry"
REGISTRY_FILE="$REGISTRY_DIR/apps.yaml"
REGISTRY_CACHE_TTL=3600  # 1 hour in seconds

# Ensure registry directory exists
ensure_registry_dir() {
    mkdir -p "$REGISTRY_DIR"
}

# Check if registry cache is fresh (< 1 hour old)
is_registry_fresh() {
    if [ ! -f "$REGISTRY_FILE" ]; then
        return 1
    fi
    
    local file_age=$(( $(date +%s) - $(stat -c %Y "$REGISTRY_FILE" 2>/dev/null || stat -f %m "$REGISTRY_FILE" 2>/dev/null || echo 0) ))
    
    if [ $file_age -lt $REGISTRY_CACHE_TTL ]; then
        return 0
    else
        return 1
    fi
}

# Fetch registry from GitHub
fetch_registry() {
    ensure_registry_dir
    
    log_info "Fetching app registry..."
    
    if curl -fsSL "$REGISTRY_URL" -o "$REGISTRY_FILE.tmp" 2>/dev/null; then
        mv "$REGISTRY_FILE.tmp" "$REGISTRY_FILE"
        log_success "Registry updated"
        return 0
    else
        rm -f "$REGISTRY_FILE.tmp"
        log_error "Failed to fetch registry from $REGISTRY_URL"
        return 1
    fi
}

# Get registry (fetch if needed)
get_registry() {
    ensure_registry_dir
    
    # Use cached registry if fresh
    if is_registry_fresh; then
        cat "$REGISTRY_FILE"
        return 0
    fi
    
    # Fetch fresh registry
    if fetch_registry; then
        cat "$REGISTRY_FILE"
        return 0
    else
        # If fetch failed but cache exists, use stale cache
        if [ -f "$REGISTRY_FILE" ]; then
            log_warning "Using cached registry (failed to update)"
            cat "$REGISTRY_FILE"
            return 0
        else
            log_error "No registry available"
            return 1
        fi
    fi
}

# Search registry
search_registry() {
    local query="$1"
    local tag="$2"
    
    local registry=$(get_registry)
    if [ -z "$registry" ]; then
        return 1
    fi
    
    # Parse YAML and filter apps
    # This is a simple grep-based parser for the registry format
    echo "$registry" | awk -v query="$query" -v tag="$tag" '
    BEGIN { 
        in_app = 0
        app_name = ""
        app_desc = ""
        app_tags = ""
        app_repo = ""
    }
    
    /^[a-zA-Z0-9_-]+:/ {
        # Print previous app if matches
        if (in_app && app_name != "") {
            match_found = 0
            if (query == "" || index(tolower(app_name), tolower(query)) > 0 || index(tolower(app_desc), tolower(query)) > 0) {
                match_found = 1
            }
            if (tag != "" && index(tolower(app_tags), tolower(tag)) == 0) {
                match_found = 0
            }
            if (match_found) {
                printf "%-20s %s\n", app_name, app_desc
            }
        }
        
        # Start new app
        in_app = 1
        app_name = $1
        gsub(/:/, "", app_name)
        app_desc = ""
        app_tags = ""
        app_repo = ""
    }
    
    /^  description:/ {
        app_desc = substr($0, index($0, ":") + 2)
        gsub(/^[ \t]+|[ \t]+$/, "", app_desc)
    }
    
    /^  tags:/ {
        getline
        while ($0 ~ /^    -/) {
            tag_value = $2
            gsub(/^[ \t]+|[ \t]+$/, "", tag_value)
            app_tags = app_tags " " tag_value
            getline
        }
    }
    
    END {
        # Print last app if matches
        if (in_app && app_name != "") {
            match_found = 0
            if (query == "" || index(tolower(app_name), tolower(query)) > 0 || index(tolower(app_desc), tolower(query)) > 0) {
                match_found = 1
            }
            if (tag != "" && index(tolower(app_tags), tolower(tag)) == 0) {
                match_found = 0
            }
            if (match_found) {
                printf "%-20s %s\n", app_name, app_desc
            }
        }
    }'
}

# Get app details from registry
get_app_info() {
    local app_name="$1"
    
    local registry=$(get_registry)
    if [ -z "$registry" ]; then
        return 1
    fi
    
    # Extract app info
    echo "$registry" | awk -v app="$app_name" '
    BEGIN { 
        in_app = 0
        found = 0
    }
    
    /^[a-zA-Z0-9_-]+:/ {
        current_app = $1
        gsub(/:/, "", current_app)
        if (current_app == app) {
            in_app = 1
            found = 1
        } else {
            in_app = 0
        }
    }
    
    in_app {
        print
    }
    
    END {
        if (!found) {
            exit 1
        }
    }'
}

# Get app repository URL
get_app_repo() {
    local app_name="$1"
    
    get_app_info "$app_name" | awk '
    /^  repo:/ {
        repo = substr($0, index($0, ":") + 2)
        gsub(/^[ \t]+|[ \t]+$/, "", repo)
        print repo
        exit
    }'
}
