#!/usr/bin/env bash
# CLI facade for deployment listing, selection, and context handling.

set -e

cmd_ps() {
  # Docker-style process listing (summary)
  local show_all=false
  local show_outside=false

  for arg in "$@"; do
    case "$arg" in
      --all|-a)
        show_all=true
        ;;
      --outside)
        show_outside=true
        ;;
    esac
  done

  log_info "TFGrid Compose v$VERSION - Docker-Style Deployment Listing"
  echo ""

  # When --outside is provided, show contracts that are not tracked in the
  # local deployment registry. This is a read-only view and does not import
  # or mutate state.
  if [ "$show_outside" = true ]; then
    if list_deployments_docker_style_outside >/dev/null 2>&1; then
      list_deployments_docker_style_outside
      echo ""
      log_info "These deployments are outside tfgrid-compose (SOURCE=outside)"
      log_info "They are visible on the grid but not tracked in the local registry"
    else
      log_warning "No outside deployments found"
    fi
    return 0
  fi

  if [ "$show_all" = true ]; then
    if list_deployments_docker_style >/dev/null 2>&1; then
      list_deployments_docker_style
      echo ""
      log_info "Select deployment: tfgrid-compose select <deployment-id|app-name>"
      log_info "Run commands: tfgrid-compose <command> [args]"
    else
      log_warning "No deployments found"
      echo ""
      log_info "Deploy an app: tfgrid-compose up <app-name>"
    fi
  else
    if list_deployments_docker_style_active_contracts >/dev/null 2>&1; then
      list_deployments_docker_style_active_contracts
      echo ""
      log_info "Select deployment: tfgrid-compose select <deployment-id|app-name>"
      log_info "Run commands: tfgrid-compose <command> [args]"
    else
      log_warning "No deployments found"
      echo ""
      log_info "Deploy an app: tfgrid-compose up <app-name>"
    fi
  fi
}

cmd_select() {
  # Select active app with multi-deployment support
  # Supports partial IDs (Docker-style): "e0c" matches "e0c0418f2a8f4d5f"
  # Use --force to select incomplete/failed deployments

  local FORCE_MODE=false
  local APP_NAME=""

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --force|-f)
        FORCE_MODE=true
        shift
        ;;
      *)
        APP_NAME="$1"
        shift
        ;;
    esac
  done

  # Force mode: bypass all validation, select directly from registry
  if [ "$FORCE_MODE" = "true" ] && [ -n "$APP_NAME" ]; then
    REGISTRY_FILE="$HOME/.config/tfgrid-compose/deployments.yaml"
    if [ ! -f "$REGISTRY_FILE" ]; then
      log_error "No deployments registry found"
      exit 1
    fi

    local DEPLOYMENT_ID=""
    local RESOLVED_APP_NAME=""

    if command_exists yq; then
      # Try exact deployment ID match first
      if yq eval ".deployments.\"$APP_NAME\"" "$REGISTRY_FILE" 2>/dev/null | grep -q "app_name"; then
        DEPLOYMENT_ID="$APP_NAME"
      else
        # Try partial ID match (Docker-style)
        local matches=$(yq eval '.deployments | keys | .[]' "$REGISTRY_FILE" 2>/dev/null | grep "^$APP_NAME" || true)
        local match_count=$(echo "$matches" | grep -c . || echo "0")

        if [ "$match_count" -eq 1 ]; then
          DEPLOYMENT_ID="$matches"
        elif [ "$match_count" -gt 1 ]; then
          log_error "Ambiguous partial ID: $APP_NAME"
          echo ""
          echo "Matches:"
          echo "$matches" | while read -r id; do
            local name=$(yq eval ".deployments.\"$id\".app_name" "$REGISTRY_FILE" 2>/dev/null)
            echo "  $id ($name)"
          done
          exit 1
        else
          # Try app name match
          DEPLOYMENT_ID=$(yq eval ".deployments | to_entries | .[] | select(.value.app_name == \"$APP_NAME\") | .key" "$REGISTRY_FILE" 2>/dev/null | head -1)
        fi
      fi

      if [ -n "$DEPLOYMENT_ID" ]; then
        RESOLVED_APP_NAME=$(yq eval ".deployments.\"$DEPLOYMENT_ID\".app_name" "$REGISTRY_FILE" 2>/dev/null)
      fi
    else
      log_error "yq is required for --force mode"
      exit 1
    fi

    if [ -z "$DEPLOYMENT_ID" ]; then
      log_error "Deployment not found: $APP_NAME"
      log_info "Use 'tfgrid-compose ps --all' to see all deployments"
      exit 1
    fi

    # Set as current app (force mode - no validation)
    CURRENT_APP_FILE="$HOME/.config/tfgrid-compose/current-app"
    mkdir -p "$(dirname "$CURRENT_APP_FILE")"
    echo "$DEPLOYMENT_ID" > "$CURRENT_APP_FILE"

    echo ""
    log_success "Selected $DEPLOYMENT_ID ($RESOLVED_APP_NAME) [forced]"

    # Show additional info from registry
    local vm_ip=$(yq eval ".deployments.\"$DEPLOYMENT_ID\".vm_ip" "$REGISTRY_FILE" 2>/dev/null)
    local mycelium_ip=$(yq eval ".deployments.\"$DEPLOYMENT_ID\".mycelium_ip" "$REGISTRY_FILE" 2>/dev/null)
    local status=$(yq eval ".deployments.\"$DEPLOYMENT_ID\".status" "$REGISTRY_FILE" 2>/dev/null)

    [ -n "$vm_ip" ] && [ "$vm_ip" != "null" ] && log_info "VM IP: $vm_ip"
    [ -n "$mycelium_ip" ] && [ "$mycelium_ip" != "null" ] && log_info "Mycelium: $mycelium_ip"
    [ -n "$status" ] && [ "$status" != "null" ] && log_info "Status: $status"
    echo ""
    return 0
  fi

  if [ -z "$APP_NAME" ]; then
    # Interactive selection
    base_dir="${STATE_BASE_DIR:-$HOME/.config/tfgrid-compose/state}"

    # Quick check: use Docker-style deployment registry instead of just state directories
    all_deployments=$(get_all_deployments 2>/dev/null || echo "")

    # Quick check: if no deployments in registry, show error immediately
    if [ -z "$all_deployments" ]; then
      echo ""
      echo "📱 Select deployment:"
      echo ""
      log_error "No deployments available for selection"
      echo ""
      log_info "No deployments found"
      echo ""
      log_info "Deploy an app: tfgrid-compose up <app-name>"
      echo ""
      exit 1
    fi

    # Build array of deployments for selection
    DEPLOYMENTS=()
    DEPLOYMENT_OPTIONS=()
    i=1

    # Get all deployments from registry
    all_deployments=$(get_all_deployments 2>/dev/null || echo "")

    # Batch fetch active contract IDs (single network call instead of per-deployment)
    local active_contract_ids=""
    local contracts_output=""
    if contracts_output=$(timeout 15 bash -c "tfgrid-compose contracts list 2>/dev/null" 2>/dev/null); then
      active_contract_ids=$(printf '%s\n' "$contracts_output" | awk '/^[0-9]+[[:space:]]/ {print $1}')
    fi

    if [ -n "$all_deployments" ] && command_exists yq; then
      # Use enhanced deployment listing with timestamps (include contract_id)
      while IFS='|' read -r deployment_id app_name vm_ip contract_id status created_at; do
        # Skip if deployment details not available
        if [ -z "$deployment_id" ] || [ -z "$app_name" ]; then
          continue
        fi

        # Skip orphaned deployments - only include those with contract IDs
        if [ -z "$contract_id" ] || [ "$contract_id" = "null" ]; then
          log_debug "Skipping orphaned deployment (no contract): $deployment_id"
          continue
        fi

        # Check if deployment state exists
        state_dir="$base_dir/$deployment_id"
        if [ ! -d "$state_dir" ]; then
          log_debug "Skipping deployment with missing state: $deployment_id"
          continue
        fi

        # PRIORITY: Only include deployments with active contracts on the grid
        # Use batch-fetched contract IDs for fast validation (no per-item network calls)
        if [ -n "$contract_id" ] && [ "$contract_id" != "null" ] && [ "$contract_id" != "" ]; then
          # Check if contract is in active list (local string match - fast)
          if printf '%s\n' "$active_contract_ids" | grep -q -E "^${contract_id}$"; then
            # This deployment has a valid contract - include it
            DEPLOYMENTS+=("$deployment_id")

            # Calculate age for display
            age=$(calculate_deployment_age "$created_at" 2>/dev/null || echo "unknown")

            # Format deployment option
            option="$i) $deployment_id $app_name ($vm_ip) - $age"
            DEPLOYMENT_OPTIONS+=("$option")

            # Mark if currently selected
            CURRENT_APP_FILE="$HOME/.config/tfgrid-compose/current-app"
            if [ -f "$CURRENT_APP_FILE" ] && [ "$(cat "$CURRENT_APP_FILE")" = "$deployment_id" ]; then
              DEPLOYMENT_OPTIONS[$((i-1))]="${DEPLOYMENT_OPTIONS[$((i-1))]} ← (currently selected)"
            fi

            ((i++))
          else
            log_debug "Skipping deployment with inactive contract: $deployment_id (contract: $contract_id)"
          fi
        fi
      done <<< "$all_deployments"
    else
      # Fallback to old app-based selection
      for app_dir in "$base_dir"/*; do
        if [ -d "$app_dir" ]; then
          app=$(basename "$app_dir")

          # Check if deployment is healthy and should be included in selection
          if timeout 5 validate_deployment_for_context "$app" 2>/dev/null; then
            DEPLOYMENTS+=("$app")

            # Get VM IP if available
            vm_ip=$(grep "^vm_ip:" "$app_dir/state.yaml" 2>/dev/null | awk '{print $2}' || echo "")

            # Get deployment status for display
            status=$(check_deployment_status "$app")

            option="$i) $app ($vm_ip) [$status]"
            DEPLOYMENT_OPTIONS+=("$option")

            # Check if currently selected
            CURRENT_APP_FILE="$HOME/.config/tfgrid-compose/current-app"
            if [ -f "$CURRENT_APP_FILE" ] && [ "$(cat "$CURRENT_APP_FILE")" = "$app" ]; then
              DEPLOYMENT_OPTIONS[$((i-1))]="${DEPLOYMENT_OPTIONS[$((i-1))]} ← (currently selected)"
            fi

            ((i++))
          else
            log_debug "Skipping unhealthy deployment: $app"
          fi
        fi
      done
    fi

    # Check if any valid deployments found
    if [ ${#DEPLOYMENTS[@]} -eq 0 ]; then
      echo ""
      echo "📱 Select deployment:"
      echo ""

      # Check if there are any deployments in the registry at all
      any_deployments=$(get_all_deployments 2>/dev/null || echo "")
      if [ -z "$any_deployments" ]; then
        log_error "No deployments found"
      else
        # There are deployments but they failed validation - list them
        echo "⚠️  Some deployments exist but may be unhealthy:"
        echo ""

        # Show deployments from registry that have active contracts but failed other validation
        # Reuse the batch-fetched active_contract_ids from earlier
        if command_exists yq; then
          while IFS='|' read -r deployment_id app_name vm_ip contract_id status created_at; do
            # Only show deployments with ACTIVE contracts on the grid
            if [ -n "$deployment_id" ] && [ -n "$contract_id" ] && [ "$contract_id" != "null" ] && [ "$contract_id" != "" ]; then
              # Check if contract is in active list (local string match - fast)
              if printf '%s\n' "$active_contract_ids" | grep -q -E "^${contract_id}$"; then
                age=$(calculate_deployment_age "$created_at" 2>/dev/null || echo "unknown")
                status_emoji="❓"
                case "$status" in
                  "active") status_emoji="✅" ;;
                  "failed") status_emoji="❌" ;;
                  "deploying") status_emoji="⏳" ;;
                esac
                echo "$status_emoji $deployment_id $app_name ($vm_ip) - $age"
              fi
            fi
          done <<< "$any_deployments"
        fi

        echo ""
        log_info "These deployments failed health validation"
        log_info "Check status with: tfgrid-compose ps"
      fi

      echo ""
      log_info "Deploy an app: tfgrid-compose up <app-name>"
      echo ""
      exit 1
    fi

    # Print header and available deployments
    echo ""
    echo "📱 Select deployment:"
    echo ""
    for option in "${DEPLOYMENT_OPTIONS[@]}"; do
      echo "$option"
    done

    echo ""
    read -p "Enter number [1-${#DEPLOYMENTS[@]}] or 'q' to quit: " choice

    if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
      echo ""
      log_info "Cancelled"
      exit 0
    fi

    # Validate choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#DEPLOYMENTS[@]} ]; then
      echo ""
      log_error "Invalid choice"
      exit 1
    fi

    # Get selected deployment (arrays are 0-indexed)
    APP_NAME="${DEPLOYMENTS[$((choice-1))]}"
  else
    # Direct selection - resolve identifier with smart matching
    RESOLVED_DEPLOYMENT=$(resolve_deployment "$APP_NAME" 2>/dev/null)
    RESOLVE_RESULT=$?

    case $RESOLVE_RESULT in
      0)
        # Single match found
        APP_NAME="$RESOLVED_DEPLOYMENT"
        ;;
      3)
        # Multiple matches - show selection menu
        echo ""
        echo "📱 Select deployment:"
        echo ""

        # Parse ambiguous results and show options
        IFS=$'\n'
        options=($RESOLVED_DEPLOYMENT)
        deployment_info=()

        for i in "${!options[@]}"; do
          deployment_id="${options[$i]}"
          details=$(get_deployment_by_id "$deployment_id" 2>/dev/null)

          if [ -n "$details" ]; then
            app_name=$(echo "$details" | grep "app_name:" | awk '{print $2}')
            vm_ip=$(echo "$details" | grep "vm_ip:" | awk '{print $2}')
            created_at=$(echo "$details" | grep "created_at:" | awk '{print $2}')
            age=$(calculate_deployment_age "$created_at" 2>/dev/null || echo "unknown")

            echo "$((i+1))) $deployment_id $app_name ($vm_ip) - $age"
            deployment_info+=("$deployment_id")
          fi
        done

        echo ""
        read -p "Enter number [1-${#options[@]}] or 'q' to quit: " choice

        if [ "$choice" = "q" ] || [ "$choice" = "Q" ]; then
          echo ""
          log_info "Cancelled"
          exit 0
        fi

        # Validate choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#options[@]} ]; then
          echo ""
          log_error "Invalid choice"
          exit 1
        fi

        # Get selected deployment
        APP_NAME="${deployment_info[$((choice-1))]}"
        ;;
      *)
        # No matches found
        log_error "Deployment not found: $APP_NAME"
        echo ""
        log_info "Use 'tfgrid-compose ps' to see available deployments"
        exit 1
        ;;
    esac
  fi

  if set_current_app "$APP_NAME"; then
    echo ""

    # Get deployment details for confirmation
    details=$(get_deployment_by_id "$APP_NAME" 2>/dev/null)
    if [ -n "$details" ]; then
      app_name=$(echo "$details" | grep "app_name:" | awk '{print $2}')
      vm_ip=$(echo "$details" | grep "vm_ip:" | awk '{print $2}')
      created_at=$(echo "$details" | grep "created_at:" | awk '{print $2}')
      age=$(calculate_deployment_age "$created_at" 2>/dev/null || echo "unknown")

      log_success "Selected $APP_NAME $app_name"
      log_info "VM: $vm_ip | Age: $age"
    else
      log_success "Selected $APP_NAME"
    fi

    log_info "Deployment-specific commands will now take precedence"
    echo ""
  else
    exit 1
  fi
}

cmd_unselect() {
  # Unselect active app
  CURRENT_APP_FILE="$HOME/.config/tfgrid-compose/current-app"
  if [ -f "$CURRENT_APP_FILE" ]; then
    CURRENT=$(cat "$CURRENT_APP_FILE")
    rm "$CURRENT_APP_FILE"
    log_success "Unselected $CURRENT"
    log_info "Built-in commands will now be used"
  else
    log_info "No app currently selected"
  fi
}

cmd_unselect_project() {
  # Unselect active project
  CONTEXT_FILE="$HOME/.config/tfgrid-compose/context.yaml"
  if [ -f "$CONTEXT_FILE" ]; then
    # Remove active_project line from context
    sed -i '/^active_project:/d' "$CONTEXT_FILE"
    log_success "Cleared project selection"
  else
    log_info "No project currently selected"
  fi
}

cmd_commands() {
  # Show app-specific commands for selected app
  CURRENT_APP=$(get_current_app)

  if [ -z "$CURRENT_APP" ]; then
    log_error "No app selected"
    echo ""
    log_info "Select an app first: tfgrid-compose select"
    exit 1
  fi

  # Resolve app path
  APP_PATH=$(resolve_app_path "$CURRENT_APP")
  if [ -z "$APP_PATH" ] || [ ! -f "$APP_PATH/tfgrid-compose.yaml" ]; then
    log_error "Cannot find app: $CURRENT_APP"
    exit 1
  fi

  echo ""
  echo "📋 Commands for $CURRENT_APP:"
  echo ""

  # Parse commands section with sed/grep (compatible approach)
  in_commands=false
  current_cmd=""
  current_desc=""
  current_args=""

  while IFS= read -r line; do
    # Check if entering commands section
    if [[ "$line" == "commands:" ]]; then
      in_commands=true
      continue
    fi

    # Exit if we hit another top-level section
    if [ "$in_commands" = true ] && [[ "$line" =~ ^[a-z] ]]; then
      break
    fi

    # Parse command entries (2-space indent)
    if [ "$in_commands" = true ]; then
      if [[ "$line" =~ ^[[:space:]]{2}([a-z_-]+):$ ]]; then
        # Print previous command if exists
        if [ -n "$current_cmd" ]; then
          if [ -n "$current_args" ]; then
            printf "  ${GREEN}%-15s${NC} %s %s\n" "$current_cmd" "$current_args" "$current_desc"
          else
            printf "  ${GREEN}%-15s${NC} %s\n" "$current_cmd" "$current_desc"
          fi
        fi

        # Start new command
        current_cmd="${BASH_REMATCH[1]}"
        current_desc=""
        current_args=""

      elif [[ "$line" =~ ^[[:space:]]{4}description:[[:space:]]*(.+)$ ]]; then
        current_desc="${BASH_REMATCH[1]}"

      elif [[ "$line" =~ ^[[:space:]]{4}args:[[:space:]]*(.+)$ ]]; then
        current_args="${BASH_REMATCH[1]}"
      fi
    fi
  done < "$APP_PATH/tfgrid-compose.yaml"

  # Print last command if exists
  if [ -n "$current_cmd" ]; then
    if [ -n "$current_args" ]; then
      printf "  ${GREEN}%-15s${NC} %s %s\n" "$current_cmd" "$current_args" "$current_desc"
    else
      printf "  ${GREEN}%-15s${NC} %s\n" "$current_cmd" "$current_desc"
    fi
  fi
}
