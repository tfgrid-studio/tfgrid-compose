#!/usr/bin/env bash
# CLI facade for contracts-related wrappers (tfcmd-based helpers and simple contracts commands).

set -e

cmd_get() {
  # Direct tfcmd wrapper - get resources
  local RESOURCE="${1:-}"
  shift || true

  case "$RESOURCE" in
    contracts)
      # List contracts using tfcmd
      log_info "TFGrid Compose v$VERSION - Contract List"
      echo ""

      # Parse options (simplified)
      local FORMAT="table"

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --format=*)
            FORMAT="${1#--format=}"
            ;;
          *)
            log_error "Unknown option: $1"
            echo ""
            echo "Usage: tfgrid-compose get contracts [--format FORMAT]"
            echo ""
            echo "Options:"
            echo "  --format=FORMAT   Output format: table, json, csv [default: table]"
            exit 1
            ;;
        esac
        shift
      done

      # Ensure tfcmd is ready and get contracts
      if ! ensure_tfcmd_login; then
        exit 1
      fi

      # Get contracts using tfcmd
      CONTRACTS_JSON=$(contracts_list_tfcmd)
      if [ $? -ne 0 ]; then
        log_error "Failed to fetch contracts"
        exit 1
      fi

      # Format and display (let tfcmd handle formatting)
      format_contract_output "$CONTRACTS_JSON" "$FORMAT"
      ;;
    contract)
      # Show single contract details
      local CONTRACT_ID="${1:-}"

      if [ -z "$CONTRACT_ID" ]; then
        log_error "Contract ID required"
        echo ""
        echo "Usage: tfgrid-compose get contract <contract-id>"
        exit 1
      fi

      if ! validate_contract_id "$CONTRACT_ID"; then
        exit 1
      fi

      log_info "Fetching contract details for ID: $CONTRACT_ID"

      # Get contract details using tfcmd
      if ! ensure_tfcmd_login; then
        exit 1
      fi

      CONTRACT_JSON=$(contracts_get_details_tfcmd "$CONTRACT_ID")
      if [ $? -ne 0 ]; then
        log_error "Failed to fetch contract details"
        exit 1
      fi

      # Display formatted details
      echo "$CONTRACT_JSON"
      ;;
    *)
      log_error "Unknown resource: $RESOURCE"
      echo ""
      echo "Available resources:"
      echo "  contracts     List all contracts"
      echo "  contract      Show contract details"
      echo ""
      echo "Usage: tfgrid-compose get <resource> [options]"
      exit 1
      ;;
  esac
}

cmd_delete() {
  # Direct tfcmd wrapper - delete resources
  local RESOURCE="${1:-}"
  shift || true

  case "$RESOURCE" in
    contracts)
      # Delete/cancel contracts using tfcmd
      if [ $# -eq 0 ]; then
        log_error "Contract ID(s) required"
        echo ""
        echo "Usage: tfgrid-compose delete contracts <contract-id> [contract-id ...]"
        echo "       tfgrid-compose delete contracts --all"
        exit 1
      fi

      # Parse options (simplified)
      local FORCE=false
      local IS_ALL=false
      local CONTRACT_IDS=()

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --force|-f)
            FORCE=true
            shift
            ;;
          --all)
            IS_ALL=true
            shift
            ;;
          -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
          *)
            # Collect contract IDs
            CONTRACT_IDS+=("$1")
            shift
            ;;
        esac
      done

      # Validate arguments
      if [ "$IS_ALL" = true ] && [ ${#CONTRACT_IDS[@]} -gt 0 ]; then
        log_error "Cannot use --all with specific contract IDs"
        exit 1
      fi

      if [ "$IS_ALL" = false ] && [ ${#CONTRACT_IDS[@]} -eq 0 ]; then
        echo ""
        echo "Usage: tfgrid-compose delete contracts [options] <contract-id> [<contract-id> ...]"
        echo "       tfgrid-compose delete contracts --all"
        echo ""
        echo "Options:"
        echo "  --force, -f       Skip confirmation prompt"
        echo "  --all             Cancel all contracts"
        exit 1
      fi

      # Ensure tfcmd is ready
      if ! ensure_tfcmd_login; then
        exit 1
      fi

      # Confirm cancellation unless forced
      if [ "$FORCE" != true ]; then
        if [ "$IS_ALL" = true ]; then
          echo ""
          echo "⚠️  WARNING: This will cancel ALL contracts!"
          echo ""
          echo "This action cannot be undone."
          echo ""
          echo -n "Are you sure you want to cancel ALL contracts? (yes/no): "
          read -r confirm
          
          if [ "$confirm" != "yes" ]; then
            echo "Cancelled"
            exit 1
          fi
        else
          echo ""
          echo "⚠️  This will cancel the following contracts:"
          for id in "${CONTRACT_IDS[@]}"; do
            echo "  - $id"
          done
          echo ""
          echo "This action cannot be undone."
          echo ""
          echo -n "Are you sure? (yes/no): "
          read -r confirm
          
          if [ "$confirm" != "yes" ]; then
            echo "Cancelled"
            exit 1
          fi
        fi
      fi

      # Perform cancellation using tfcmd
      if [ "$IS_ALL" = true ]; then
        if contracts_cancel_batch_tfcmd "--all"; then
          exit 0
        else
          exit 1
        fi
      else
        # Validate all contract IDs first
        for id in "${CONTRACT_IDS[@]}"; do
          if ! validate_contract_id "$id"; then
            exit 1
          fi
        done
        
        local ids_string
        ids_string=$(printf '%s\n' "${CONTRACT_IDS[@]}" | tr '\n' ' ')
        if contracts_cancel_batch_tfcmd "$ids_string"; then
          exit 0
        else
          exit 1
        fi
      fi
      ;;
    contract)
      # Delete single contract
      local CONTRACT_ID="${1:-}"
      shift || true

      if [ -z "$CONTRACT_ID" ]; then
        log_error "Contract ID required"
        echo ""
        echo "Usage: tfgrid-compose delete contract <contract-id> [--force]"
        exit 1
      fi

      if ! validate_contract_id "$CONTRACT_ID"; then
        exit 1
      fi

      # Parse options
      local FORCE=false
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --force|-f)
            FORCE=true
            shift
            ;;
          *)
            log_error "Unknown option: $1"
            exit 1
            ;;
        esac
      done

      # Ensure tfcmd is ready
      if ! ensure_tfcmd_login; then
        exit 1
      fi

      # Confirm deletion unless forced
      if [ "$FORCE" != true ]; then
        echo ""
        echo "⚠️  This will cancel contract $CONTRACT_ID"
        echo "This action cannot be undone."
        echo ""
        echo -n "Are you sure? (yes/no): "
        read -r confirm
        
        if [ "$confirm" != "yes" ]; then
          echo "Cancelled"
          exit 1
        fi
      fi

      # Delete single contract
      if contracts_cancel_single_tfcmd "$CONTRACT_ID"; then
        exit 0
      else
        exit 1
      fi
      ;;
    *)
      log_error "Unknown resource: $RESOURCE"
      echo ""
      echo "Available resources:"
      echo "  contracts     Delete contracts (single or batch)"
      echo "  contract      Delete single contract"
      echo ""
      echo "Usage: tfgrid-compose delete <resource> [options] <id...>"
      exit 1
      ;;
  esac
}

cmd_contracts() {
  # Simple tfgrid-compose contracts wrapper using core contract-manager functions
  local SUBCOMMAND="${1:-list}"
  shift || true

  case "$SUBCOMMAND" in
    list)
      # List contracts using simple wrapper
      contracts_list
      ;;
    show)
      # Show contract details (not yet implemented in simple wrapper)
      echo "Contract details not implemented in simple wrapper"
      echo "Use: tfcmd get contract <contract-id>"
      exit 1
      ;;
    delete)
      # Delete contracts using simple wrapper
      # Supports:
      #   tfgrid-compose contracts delete <contract-id>
      #   tfgrid-compose contracts delete <id1> <id2> <id3>
      #   tfgrid-compose contracts delete <id1> <id2> --yes
      #   tfgrid-compose contracts delete --all
      #   tfgrid-compose contracts delete --all --yes
      
      if [ "${1:-}" = "--all" ]; then
        shift || true
        if [ "${1:-}" = "--yes" ]; then
          contracts_cancel_all "--yes"
        else
          contracts_cancel_all
        fi
        exit 0
      fi
      
      local CONTRACT_IDS=()
      local SKIP_CONFIRM=false
      
      while [ $# -gt 0 ]; do
        case "$1" in
          --yes)
            SKIP_CONFIRM=true
            shift
            ;;
          --all)
            log_error "Cannot use --all with specific contract IDs"
            exit 1
            ;;
          *)
            CONTRACT_IDS+=("$1")
            shift
            ;;
        esac
      done
      
      if [ ${#CONTRACT_IDS[@]} -eq 0 ]; then
        echo ""
        echo "Usage: tfgrid-compose contracts delete <contract-id> [<contract-id>...] [--yes]"
        echo "       tfgrid-compose contracts delete --all [--yes]"
        echo ""
        echo "Examples:"
        echo "  tfgrid-compose contracts delete 12345"
        echo "  tfgrid-compose contracts delete 12345 67890 11111"
        echo "  tfgrid-compose contracts delete 12345 67890 --yes"
        echo "  tfgrid-compose contracts delete --all --yes"
        exit 1
      fi
      
      # Deduplicate contract IDs
      local UNIQUE_IDS
      UNIQUE_IDS=($(printf '%s\n' "${CONTRACT_IDS[@]}" | sort -u))
      
      # Single contract - use existing function
      if [ ${#UNIQUE_IDS[@]} -eq 1 ]; then
        contracts_delete "${UNIQUE_IDS[0]}"
        exit 0
      fi
      
      # Multi-contract delete via loop
      if [ "$SKIP_CONFIRM" != true ]; then
        echo ""
        echo "⚠️  This will cancel the following contracts:"
        for id in "${UNIQUE_IDS[@]}"; do
          echo "  - $id"
        done
        echo ""
        echo "This action cannot be undone."
        echo ""
        echo -n "Are you sure? (yes/no): "
        read -r confirm
        if [ "$confirm" != "yes" ]; then
          echo "Cancelled"
          exit 1
        fi
      fi
      
      local failed=0
      for id in "${UNIQUE_IDS[@]}"; do
        if ! contracts_delete "$id"; then
          echo "Failed to cancel contract $id" >&2
          failed=1
        fi
      done
      
      exit $failed
      ;;
    *)
      log_error "Unknown contracts subcommand: $SUBCOMMAND"
      echo ""
      echo "Available subcommands: list, show, delete"
      exit 1
      ;;
  esac
}
