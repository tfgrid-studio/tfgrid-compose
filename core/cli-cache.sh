#!/usr/bin/env bash
# CLI facade for cache management commands.

set -e

cmd_cache() {
  # Cache management command
  CACHE_SUBCOMMAND="${1:-status}"
  shift || true
  
  case "$CACHE_SUBCOMMAND" in
    status|health)
      # Show cache status
      log_info "TFGrid Compose v$VERSION - Cache Status"
      echo ""
      
      list_cached_apps_enhanced
      echo ""
      log_info "Run 't cache list' for detailed status"
      ;;
      
    list)
      # List all cached apps with detailed status
      log_info "TFGrid Compose v$VERSION - Cached Apps"
      echo ""
      
      list_cached_apps_enhanced
      echo ""
      log_info "Apps with [needs update] can be refreshed with 't update <app-name>'"
      ;;
      
    registry)
      # Show all registry apps status (cached and uncached)
      log_info "TFGrid Compose v$VERSION - Registry Apps Status"
      echo ""
      
      show_registry_apps_status
      ;;
      
    preload)
      # Pre-cache all registry apps
      log_info "TFGrid Compose v$VERSION - Pre-Cache Registry Apps"
      echo ""
      
      pre_cache_registry_apps
      ;;
      
    monitor)
      # Start cache monitoring dashboard
      log_info "TFGrid Compose v$VERSION - Cache Monitor"
      echo ""
      
      if [ -f "$DEPLOYER_ROOT/core/cache-dashboard.sh" ]; then
        source "$DEPLOYER_ROOT/core/cache-dashboard.sh"
        cache_dashboard_monitor "$@"
      else
        log_error "Cache dashboard not found"
        exit 1
      fi
      ;;
      
    dashboard)
      # Show cache health dashboard
      log_info "TFGrid Compose v$VERSION - Cache Dashboard"
      echo ""
      
      if [ -f "$DEPLOYER_ROOT/core/cache-dashboard.sh" ]; then
        source "$DEPLOYER_ROOT/core/cache-dashboard.sh"
        cache_dashboard_show
      else
        log_error "Cache dashboard not found"
        exit 1
      fi
      ;;
      
    outdated)
      # List apps that need updates
      log_info "TFGrid Compose v$VERSION - Outdated Apps"
      echo ""
      
      list_outdated_apps
      ;;
      
    refresh)
      # Refresh outdated apps automatically
      log_info "TFGrid Compose v$VERSION - Refresh Outdated Apps"
      echo ""
      
      refresh_outdated_apps
      ;;
      
    validate)
      # Validate cached apps
      log_info "TFGrid Compose v$VERSION - Validate Cache"
      echo ""
      
      local app_name="${1:-}"
      if [ -n "$app_name" ]; then
        # Validate specific app
        if validate_cached_app "$app_name"; then
          echo "✅ $app_name cache validation passed"
        else
          echo "❌ $app_name cache validation failed"
          exit 1
        fi
      else
        # Validate all cached apps
        echo "Validating all cached apps..."
        echo ""
        
        failed_count=0
        total_count=0
        
        for app_dir in "$APPS_CACHE_DIR"/*; do
          if [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]; then
            name=$(basename "$app_dir")
            ((total_count++))
            
            if validate_cached_app "$name"; then
              echo "✅ $name"
            else
              echo "❌ $name"
              ((failed_count++))
            fi
          fi
        done
        
        echo ""
        log_info "Validated $total_count apps, $failed_count failures"
        
        if [ $failed_count -gt 0 ]; then
          exit 1
        fi
      fi
      ;;
      
    clear)
      # Clean cache
      CACHE_TARGET="${1:-}"
      
      if [ -z "$CACHE_TARGET" ] || [ "$CACHE_TARGET" = "--all" ]; then
        # Clear all cache
        if [ "$CACHE_TARGET" = "--all" ]; then
          log_info "Clearing ALL cache..."
          clean_app_cache "" --force
          log_success "All cache cleared"
        else
          echo "⚠️  This will remove ALL cached apps"
          echo "Apps will need to be downloaded again"
          echo ""
          read -p "Continue? (y/N): " -n 1 -r
          echo
          if [[ $REPLY =~ ^[Yy]$ ]]; then
            clean_app_cache "" --force
            log_success "All cache cleared"
          else
            log_info "Cancelled"
          fi
        fi
      else
        # Clear specific app
        clean_app_cache "$CACHE_TARGET"
      fi
      ;;
      
    info)
      # Show cache information
      log_info "TFGrid Compose v$VERSION - Cache Information"
      echo ""
      
      echo "Cache Directory: $APPS_CACHE_DIR"
      echo "Metadata Directory: $CACHE_METADATA_DIR"
      echo ""
      
      # Show cache statistics
      total_apps=0
      healthy_apps=0
      stale_apps=0
      invalid_apps=0
      
      for app_dir in "$APPS_CACHE_DIR"/*; do
        if [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]; then
          app_name=$(basename "$app_dir")
          health=$(get_cache_health "$app_name")
          status=$(echo "$health" | jq -r '.status')
          
          ((total_apps++))
          case "$status" in
            "healthy") ((healthy_apps++)) ;;
            "stale") ((stale_apps++)) ;;
            "invalid") ((invalid_apps++)) ;;
          esac
        fi
      done
      
      echo "Cache Statistics:"
      echo "  Total apps: $total_apps"
      echo "  Healthy: $healthy_apps"
      echo "  Stale: $stale_apps"
      echo "  Invalid: $invalid_apps"
      echo ""
      
      log_info "Use 't cache list' for detailed status"
      ;;
      
    --help|-h|"")
      # Show help
      echo ""
      echo "🔄 Cache Management"
      echo ""
      echo "Usage: tfgrid-compose cache <subcommand> [options]"
      echo ""
      echo "Subcommands:"
      echo "  status, health      Show cache overview"
      echo "  list               List all cached apps with status"
      echo "  registry           Show all registry apps (cached/uncached)"
      echo "  preload            Pre-cache all registry apps"
      echo "  monitor            Start real-time cache monitoring dashboard"
      echo "  dashboard          Show cache health dashboard"
      echo "  outdated           List apps that need updates"
      echo "  refresh            Refresh outdated apps"
      echo "  validate [app]     Validate cache for app or all apps"
      echo "  clear [app|--all]  Clear cache for app or all apps"
      echo "  info               Show cache directories and stats"
      ;;
      
    *)
      log_error "Unknown cache subcommand: $CACHE_SUBCOMMAND"
      echo "Use 'tfgrid-compose cache --help' for usage."
      return 1
      ;;
  esac
}
