#!/usr/bin/env bash
# TFGrid Compose - Pre-Cache Registry Apps Module
# Proactively cache all apps from registry for update/management without deployment

# Get all apps from registry
get_all_registry_apps() {
    local registry_file="$TFGRID_STUDIO_DIR/app-registry/registry/apps.yaml"
    
    if [ ! -f "$registry_file" ]; then
        log_error "Registry file not found: $registry_file"
        return 1
    fi
    
    # Extract all app names and repos from registry
    awk '
    /^    - name:/ {
        getline
        while ($0 ~ /^[[:space:]]+repo:/) {
            repo = $0
            gsub(/^[[:space:]]+repo:[[:space:]]*/, "", repo)
            gsub(/[[:space:]]+$/, "", repo)
            print name "|" repo
            break
        }
    }
    
    /^    - name:/ {
        name = $3
        gsub(/^[ \t]+|[ \t]+$/, "", name)
    }
    ' "$registry_file"
}

# Pre-cache all registry apps
pre_cache_registry_apps() {
    log_info "Pre-caching all registry apps..."
    echo ""
    
    local apps_data=$(get_all_registry_apps)
    if [ $? -ne 0 ] || [ -z "$apps_data" ]; then
        log_error "Failed to get registry apps"
        return 1
    fi
    
    local cached_count=0
    local failed_count=0
    
    echo "$apps_data" | while IFS='|' read -r app_name repo_url; do
        if [ -n "$app_name" ] && [ -n "$repo_url" ]; then
            echo "📦 Caching $app_name..."
            
            # Convert GitHub URL to Git clone URL
            local clone_url="https://$repo_url.git"
            
            if cache_app "$app_name" "$clone_url"; then
                echo "  ✅ Cached $app_name"
                ((cached_count++))
            else
                echo "  ❌ Failed to cache $app_name"
                ((failed_count++))
            fi
        fi
    done
    
    echo ""
    if [ $cached_count -gt 0 ]; then
        log_success "Pre-cached $cached_count apps from registry"
    fi
    
    if [ $failed_count -gt 0 ]; then
        log_warning "Failed to cache $failed_count apps"
    fi
    
    if [ $cached_count -eq 0 ] && [ $failed_count -eq 0 ]; then
        log_info "No apps to cache (registry may be empty)"
    fi
}

# Update all registry apps (regardless of deployment status)
update_all_registry_apps() {
    log_info "Updating all registry apps..."
    echo ""
    
    # First ensure all registry apps are cached
    pre_cache_registry_apps
    echo ""
    
    # Then update all cached apps
    log_info "Updating cached apps to latest commits..."
    refresh_outdated_apps
    
    echo ""
    log_success "Registry apps update complete"
}

# Show registry apps status (including non-cached)
show_registry_apps_status() {
    local registry_file="$TFGRID_STUDIO_DIR/app-registry/registry/apps.yaml"
    
    if [ ! -f "$registry_file" ]; then
        log_error "Registry file not found: $registry_file"
        return 1
    fi
    
    echo "📋 Registry Apps Status:"
    echo ""
    
    # Get all registry apps
    local apps_data=$(get_all_registry_apps)
    if [ $? -ne 0 ] || [ -z "$apps_data" ]; then
        log_error "Failed to get registry apps"
        return 1
    fi
    
    local total_apps=0
    local cached_apps=0
    local updated_apps=0
    
    echo "$apps_data" | while IFS='|' read -r app_name repo_url; do
        if [ -n "$app_name" ] && [ -n "$repo_url" ]; then
            ((total_apps++))
            
            if is_app_cached "$app_name"; then
                ((cached_apps++))
                local health=$(get_cache_health "$app_name")
                local status=$(echo "$health" | jq -r '.status')
                local needs_update=$(echo "$health" | jq -r '.needs_update')
                
                case "$status" in
                    "healthy") icon="✅" ;;
                    "stale") icon="🔄" ;;
                    "invalid") icon="⚠️" ;;
                    *) icon="❓" ;;
                esac
                
                local update_flag=""
                if [ "$needs_update" = "true" ]; then
                    update_flag=" [needs update]"
                    ((updated_apps++))
                fi
                
                echo "$icon $app_name$update_flag"
            else
                echo "📦 $app_name (not cached)"
            fi
        fi
    done
    
    echo ""
    echo "📊 Summary: $cached_apps/$total_apps cached"
    
    if [ $updated_apps -gt 0 ]; then
        echo "🔄 $updated_apps apps need updates"
        echo ""
        echo "Run 't cache refresh' to update all"
    fi
}

# Export functions
export -f pre_cache_registry_apps
export -f update_all_registry_apps
export -f show_registry_apps_status
export -f get_all_registry_apps