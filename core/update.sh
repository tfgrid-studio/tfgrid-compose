#!/usr/bin/env bash

# Update management module for tfgrid-compose CLI
# Encapsulates logic for updating the tfgrid-compose binary and app cache.

set -e

cmd_update() {
  local UPDATE_SUBCOMMAND="${1:-}"
  shift || true

  case "$UPDATE_SUBCOMMAND" in
    registry)
      _update_registry_and_apps "$@"
      ;;
    ""|"")
      _update_tfgrid_compose
      ;;
    --all-apps)
      _update_all_apps
      ;;
    *)
      _update_single_app "$UPDATE_SUBCOMMAND"
      ;;
  esac
}

_update_tfgrid_compose() {
  log_info "TFGrid Compose $VERSION - Update"
  echo ""

  if ! command -v curl >/dev/null 2>&1; then
    log_error "curl is required for update. Please install curl first."
    return 1
  fi

  if ! command -v git >/dev/null 2>&1; then
    log_error "git is required for update. Please install git first."
    return 1
  fi

  echo "🔄 Fetching latest version from GitHub..."
  echo ""

  local LATEST_COMMIT
  LATEST_COMMIT=$(get_latest_tfgrid_compose_version)
  if [ "$LATEST_COMMIT" = "unknown" ]; then
    log_error "Failed to fetch latest commit from GitHub"
    return 1
  fi

  local CURRENT_VERSION_INFO
  CURRENT_VERSION_INFO=$(get_tfgrid_compose_version)
  local CURRENT_COMMIT
  CURRENT_COMMIT=$(echo "$CURRENT_VERSION_INFO" | jq -r '.git_commit // "unknown"')

  echo "📊 Version Comparison:"
  echo "  Current commit: $CURRENT_COMMIT"
  echo "  Latest commit:  $LATEST_COMMIT"
  echo ""

  if [ "$CURRENT_COMMIT" = "$LATEST_COMMIT" ] && [ "$CURRENT_COMMIT" != "unknown" ]; then
    echo "✨ Already at latest version: $LATEST_COMMIT"
    echo ""
    echo "🧪 Test with: tfgrid-compose --version"
    echo ""
    return 0
  fi

  echo "📋 Update Summary:"
  echo "  → Current: $CURRENT_COMMIT"
  echo "  → Latest:  $LATEST_COMMIT"
  echo ""

  local DASHBOARD_WAS_RUNNING=false
  local DASHBOARD_HOME="$HOME/.config/tfgrid-compose/dashboard"
  local DASHBOARD_PID_FILE="$DASHBOARD_HOME/dashboard.pid"

  if [ -f "$DASHBOARD_PID_FILE" ]; then
    local DASHBOARD_PID
    DASHBOARD_PID=$(cat "$DASHBOARD_PID_FILE" 2>/dev/null || true)
    if [ -n "$DASHBOARD_PID" ] && ps -p "$DASHBOARD_PID" >/dev/null 2>&1; then
      DASHBOARD_WAS_RUNNING=true
      log_info "Stopping running dashboard before update (pid $DASHBOARD_PID)..."
      kill "$DASHBOARD_PID" 2>/dev/null || true
      for _ in $(seq 1 50); do
        if ! ps -p "$DASHBOARD_PID" >/dev/null 2>&1; then
          break
        fi
        sleep 0.1
      done
      rm -f "$DASHBOARD_PID_FILE"
    else
      rm -f "$DASHBOARD_PID_FILE"
    fi
  fi

  local TEMP_DIR
  TEMP_DIR=$(mktemp -d)
  trap "rm -rf '$TEMP_DIR'" EXIT

  if ! git clone --depth 1 https://github.com/tfgrid-studio/tfgrid-compose.git "$TEMP_DIR/tfgrid-compose" >/dev/null 2>&1; then
    log_error "Failed to download latest version from GitHub"
    return 1
  fi

  echo "📦 Installing latest version..."

  local CURRENT_VERSION_FILE="$HOME/.config/tfgrid-compose/VERSION"
  echo "$LATEST_COMMIT" > "$CURRENT_VERSION_FILE"

  cd "$TEMP_DIR/tfgrid-compose"
  if ! make install >/dev/null 2>&1; then
    log_error "Failed to install latest version"
    return 1
  fi

  echo ""
  log_success "✅ Successfully updated to latest version!"
  echo ""

  if [ "$DASHBOARD_WAS_RUNNING" = true ]; then
    log_info "Restarting TFGrid Studio dashboard with updated version..."
    if command -v tfgrid-compose >/dev/null 2>&1; then
      tfgrid-compose dashboard start >/dev/null 2>&1 || true
    fi
    echo ""
  fi

  echo "🔍 Detection Method: Dynamic Git commit detection"
  echo "🧪 Test with: tfgrid-compose --version"
  echo ""
  echo "💡 Tip: Use 't update registry' to update apps + registry data"
}

_update_all_apps() {
  log_info "TFGrid Compose v$VERSION - Update All Apps"
  echo ""

  log_info "Updating all cached apps..."
  refresh_outdated_apps

  echo ""
  log_success "✅ App cache update complete!"
}

_update_registry_and_apps() {
  local FORCE_UPDATE=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force|-f)
        FORCE_UPDATE=true
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  if [ "$FORCE_UPDATE" = true ]; then
    log_info "TFGrid Compose $VERSION - Update Registry + Apps (Forced)"
  else
    log_info "TFGrid Compose $VERSION - Update Registry + Apps"
  fi
  echo ""

  log_info "🔄 Updating registry data and checking all app commits..."
  echo ""

  if update_registry "$FORCE_UPDATE"; then
    log_success "✅ Registry data updated successfully!"
  else
    log_error "❌ Failed to update registry data"
    return 1
  fi

  echo ""
  echo "📊 Checking app cache status..."

  local outdated_apps_found=false
  local updated_count=0
  local skipped_count=0

  local CURRENT_VERSION_INFO
  CURRENT_VERSION_INFO=$(get_tfgrid_compose_version)
  local CURRENT_COMMIT
  CURRENT_COMMIT=$(echo "$CURRENT_VERSION_INFO" | jq -r '.git_commit // "unknown"')

  echo ""
  echo "🔍 App Cache Status:"
  echo "  TFGrid Compose: $CURRENT_COMMIT"
  echo ""

  for app_dir in "$APPS_CACHE_DIR"/*; do
    if [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]; then
      local app_name
      app_name=$(basename "$app_dir")

      cd "$app_dir"
      local cached_commit
      cached_commit=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")
      cd - >/dev/null

      if cache_needs_update "$app_name"; then
        outdated_apps_found=true

        cd "$app_dir"
        local latest_commit
        latest_commit=$(git fetch --quiet origin main 2>/dev/null && git rev-parse --short=7 origin/main 2>/dev/null || echo "unknown")
        cd - >/dev/null

        if [ "$latest_commit" != "unknown" ] && [ "$cached_commit" != "$latest_commit" ]; then
          echo "🔄 $app_name:"
          echo "    Cached: $cached_commit"
          echo "    Latest: $latest_commit"

          if update_cached_app "$app_name"; then
            ((updated_count++))
            echo "    ✅ Updated successfully"
          else
            echo "    ⚠️  Update failed, using cached version"
          fi
        else
          ((skipped_count++))
          echo "⏭️  $app_name: No updates available ($cached_commit)"
        fi
      else
        echo "✅ $app_name: Up to date ($cached_commit)"
      fi
    fi
  done

  echo ""
  if [ "$outdated_apps_found" = true ]; then
    echo "📈 Update Summary:"
    echo "  Apps updated: $updated_count"
    echo "  Apps skipped: $skipped_count"
    echo "  Total cached apps checked"
    echo ""
    log_success "✅ Registry + app cache update complete!"
    echo ""
    echo "🧪 Test with: tfgrid-compose cache list"
    echo "📱 Browse updated apps: tfgrid-compose search"
  else
    log_success "✅ All apps are already up to date!"
    echo ""
    echo "🧪 Check cache status: tfgrid-compose cache status"
  fi
}

_update_single_app() {
  local APP_NAME="$1"

  if [ -z "$APP_NAME" ]; then
    log_error "Usage: tfgrid-compose update [registry|app-name|--all-apps]"
    echo ""
    echo "Update tfgrid-compose binary only (fast):"
    echo "  tfgrid-compose update"
    echo ""
    echo "🎉 COMPREHENSIVE UPDATE (recommended):"
    echo "  tfgrid-compose update registry"
    echo "     → Updates registry metadata + ALL cached apps"
    echo ""
    echo "Update specific app only:"
    echo "  tfgrid-compose update tfgrid-ai-stack"
    echo ""
    echo "Update all cached apps only:"
    echo "  tfgrid-compose update --all-apps"
    return 1
  fi

  log_info "TFGrid Compose $VERSION - Update App: $APP_NAME"
  echo ""

  if ! is_app_cached "$APP_NAME"; then
    log_error "App '$APP_NAME' is not cached"
    log_info "Deploy the app first or install it from registry"
    return 1
  fi

  local app_dir="$APPS_CACHE_DIR/$APP_NAME"
  cd "$app_dir" 2>/dev/null || true
  local current_commit
  current_commit=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")
  cd - >/dev/null

  echo "📊 Current Status:"
  echo "  App: $APP_NAME"
  echo "  Current commit: $current_commit"
  echo ""

  echo "🔄 Fetching latest commits..."
  cd "$app_dir"
  local fetch_result="unknown"
  if git fetch --quiet origin main 2>/dev/null; then
    fetch_result=$(git rev-parse --short=7 origin/main 2>/dev/null || echo "unknown")
  elif git fetch --quiet origin master 2>/dev/null; then
    fetch_result=$(git rev-parse --short=7 origin/master 2>/dev/null || echo "unknown")
  fi
  cd - >/dev/null

  if [ "$fetch_result" != "unknown" ]; then
    echo "  Latest commit:  $fetch_result"
    echo ""

    if [ "$current_commit" = "$fetch_result" ]; then
      echo "✨ Already at latest version: $current_commit"
      echo ""
      echo "🧪 Test with: tfgrid-compose cache list"
      return 0
    else
      echo "📋 Update Available:"
      echo "  → Current: $current_commit"
      echo "  → Latest:  $fetch_result"
      echo ""
    fi
  else
    echo "  Latest commit: Unable to fetch"
    echo ""
    log_warning "Could not fetch latest commits, attempting update anyway..."
  fi

  if update_cached_app "$APP_NAME"; then
    echo ""
    log_success "✅ Updated $APP_NAME successfully!"
    echo ""

    local new_app_dir="$APPS_CACHE_DIR/$APP_NAME"
    cd "$new_app_dir" 2>/dev/null || true
    local new_commit
    new_commit=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")
    cd - >/dev/null

    if [ "$new_commit" != "unknown" ]; then
      echo "🔍 New commit: $new_commit"
      echo "🔍 Detection Method: Git-based commit tracking"
    fi

    echo ""
    echo "🧪 Test with: tfgrid-compose cache list"
    echo "📱 Deploy updated app: tfgrid-compose up $APP_NAME"
  else
    echo ""
    log_warning "⚠️  Update failed for $APP_NAME (using cached version)"
    echo ""
    echo "🔧 Troubleshooting:"
    echo "  • Check network connectivity"
    echo "  • Verify repository access: git ls-remote origin"
    echo "  • Clear cache: tfgrid-compose cache clear $APP_NAME"
    echo "  • Try manual update: cd ~/.config/tfgrid-compose/apps/$APP_NAME && git pull"
  fi
}
