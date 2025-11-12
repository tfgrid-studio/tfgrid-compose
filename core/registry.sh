#!/usr/bin/env bash
# TFGrid Compose - Registry Module
# Handles fetching and caching the app registry from GitHub

# Registry configuration
REGISTRY_URL="https://raw.githubusercontent.com/tfgrid-studio/app-registry/main/registry/apps.yaml"
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
    
    # Parse YAML and filter apps (supports nested apps.official/apps.verified format)
    echo "$registry" | awk -v query="$query" -v tag="$tag" '
    BEGIN { 
        in_app = 0
        app_name = ""
        app_desc = ""
        app_tags = ""
    }
    
    /^    - name:/ {
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
        app_name = $3
        gsub(/^[ \t]+|[ \t]+$/, "", app_name)
        app_desc = ""
        app_tags = ""
    }
    
    /^      description:/ {
        app_desc = substr($0, index($0, "description:") + 12)
        gsub(/^[ \t]+|[ \t]+$/, "", app_desc)
    }
    
    /^        - / && in_app {
        tag_value = $2
        gsub(/^[ \t]+|[ \t]+$/, "", tag_value)
        app_tags = app_tags " " tag_value
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
    
    # Extract app info from nested apps.official/apps.verified format
    echo "$registry" | awk -v app="$app_name" '
    BEGIN { 
        in_app = 0
        found = 0
    }
    
    /^    - name:/ {
        current_app = $3
        gsub(/^[ \t]+|[ \t]+$/, "", current_app)
        if (current_app == app) {
            in_app = 1
            found = 1
            print
        } else {
            in_app = 0
        }
    }
    
    in_app && /^      / {
        print
    }
    
    /^    - name:/ && in_app && current_app != app {
        in_app = 0
    }
    
    END {
        if (!found) {
            exit 1
        }
    }'
}

# Update registry - comprehensive update of registry metadata and cached apps
update_registry() {
    echo ""
    echo "🔄 TFGrid Compose - Unified Registry Update"
    echo "==========================================="
    echo ""
    
    # Step 1: Update registry metadata
    echo "📡 Updating registry metadata..."
    if fetch_registry; then
        echo "✅ Registry metadata updated successfully"
    else
        echo "❌ Failed to update registry metadata"
        return 1
    fi
    
    echo ""
    
    # Step 2: Update all cached app repositories
    echo "📦 Updating cached app repositories..."
    if command -v pre_cache_registry_apps >/dev/null 2>&1; then
        pre_cache_registry_apps
        echo "✅ App repositories updated successfully"
    else
        echo "⚠️  pre_cache_registry_apps not available, skipping app updates"
        echo "   You can run 't cache preload' to update app repositories manually"
    fi
    
    echo ""
    echo "🎉 Registry update complete!"
    echo ""
    return 0
}

# Get app repository URL
get_app_repo() {
    local app_name="$1"
    
    local registry=$(get_registry)
    if [ -z "$registry" ]; then
        return 1
    fi
    
    # Extract repo URL directly
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
    
    in_app && /^      repo:/ {
        repo = substr($0, index($0, "repo:") + 5)
        gsub(/^[ \t]+|[ \t]+$/, "", repo)
        # Convert github.com/org/repo to https://
        if (index(repo, "http") == 0) {
            repo = "https://" repo
        }
        print repo
        exit
    }'
}
