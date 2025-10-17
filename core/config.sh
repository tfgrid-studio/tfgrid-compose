#!/usr/bin/env bash
# TFGrid Compose - Config Module
# Handles configuration management

# Config commands

# List all configuration
config_list() {
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        echo ""
        log_error "No credentials found"
        echo ""
        echo "You need to login first:"
        echo "  tfgrid-compose login"
        echo ""
        return 1
    fi
    
    echo ""
    log_info "TFGrid Compose Configuration"
    echo ""
    echo "File: $CREDENTIALS_FILE"
    echo ""
    
    load_credentials
    
    # Show mnemonic (never expose any part)
    if [ -n "$TFGRID_MNEMONIC" ]; then
        local word_count=$(echo "$TFGRID_MNEMONIC" | wc -w | tr -d ' ')
        echo "threefold.mnemonic    ********** ($word_count words)"
    else
        echo "threefold.mnemonic    (not set)"
    fi
    
    # Show GitHub token (never expose any part)
    if [ -n "$TFGRID_GITHUB_TOKEN" ]; then
        echo "github.token          ********** (configured)"
    else
        echo "github.token          (not set)"
    fi
    
    # Show Gitea URL (safe to show - it's a URL)
    if [ -n "$TFGRID_GITEA_URL" ]; then
        echo "gitea.url             $TFGRID_GITEA_URL"
    else
        echo "gitea.url             (not set)"
    fi
    
    # Show Gitea token (never expose any part)
    if [ -n "$TFGRID_GITEA_TOKEN" ]; then
        echo "gitea.token           ********** (configured)"
    else
        echo "gitea.token           (not set)"
    fi
    
    echo ""
}

# Get specific config value
config_get() {
    local key="$1"
    
    if [ -z "$key" ]; then
        echo ""
        log_error "Key is required"
        echo ""
        echo "Usage:"
        echo "  tfgrid-compose config get <key>"
        echo ""
        echo "Examples:"
        echo "  tfgrid-compose config get gitea-url    # Safe to retrieve"
        echo ""
        echo "Note: Secrets (mnemonic, tokens) cannot be retrieved via CLI"
        echo "      for security. Use 'tfgrid-compose config list' to see status."
        echo ""
        return 1
    fi
    
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        log_error "No credentials found. Run: tfgrid-compose login"
        return 1
    fi
    
    load_credentials
    
    case "$key" in
        threefold.mnemonic|mnemonic)
            echo ""
            log_error "Mnemonic cannot be retrieved for security reasons"
            echo ""
            echo "The mnemonic is used internally for deployments but cannot"
            echo "be displayed via CLI to prevent accidental exposure."
            echo ""
            echo "To verify it's configured:"
            echo "  tfgrid-compose config list"
            echo ""
            echo "To view or edit the file directly (requires proper permissions):"
            echo "  cat $CREDENTIALS_FILE"
            echo "  vi $CREDENTIALS_FILE"
            echo ""
            return 1
            ;;
        github.token|github-token)
            echo ""
            log_error "GitHub token cannot be retrieved for security reasons"
            echo ""
            echo "Tokens are used internally but cannot be displayed via CLI"
            echo "to prevent accidental exposure."
            echo ""
            echo "To verify it's configured:"
            echo "  tfgrid-compose config list"
            echo ""
            echo "To view the file directly (requires proper permissions):"
            echo "  cat $CREDENTIALS_FILE"
            echo ""
            return 1
            ;;
        gitea.url|gitea-url)
            if [ -n "$TFGRID_GITEA_URL" ]; then
                echo "$TFGRID_GITEA_URL"
            else
                log_error "Gitea URL not set"
                return 1
            fi
            ;;
        gitea.token|gitea-token)
            echo ""
            log_error "Gitea token cannot be retrieved for security reasons"
            echo ""
            echo "Tokens are used internally but cannot be displayed via CLI"
            echo "to prevent accidental exposure."
            echo ""
            echo "To verify it's configured:"
            echo "  tfgrid-compose config list"
            echo ""
            echo "To view the file directly (requires proper permissions):"
            echo "  cat $CREDENTIALS_FILE"
            echo ""
            return 1
            ;;
        *)
            log_error "Unknown key: $key"
            echo ""
            echo "Valid keys:"
            echo "  threefold.mnemonic (or mnemonic)   [secret - cannot retrieve]"
            echo "  github.token (or github-token)     [secret - cannot retrieve]"
            echo "  gitea.url (or gitea-url)           [safe to retrieve]"
            echo "  gitea.token (or gitea-token)       [secret - cannot retrieve]"
            echo ""
            echo "To view all configured values (masked):"
            echo "  tfgrid-compose config list"
            return 1
            ;;
    esac
}

# Set config value
config_set() {
    local key="$1"
    local value="$2"
    
    if [ -z "$key" ] || [ -z "$value" ]; then
        echo ""
        log_error "Both key and value are required"
        echo ""
        echo "Usage:"
        echo "  tfgrid-compose config set <key> <value>"
        echo ""
        echo "Examples:"
        echo "  tfgrid-compose config set github-token ghp_xyz123"
        echo "  tfgrid-compose config set gitea-url https://git.example.com"
        echo ""
        return 1
    fi
    
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        log_error "No credentials found. Run: tfgrid-compose login"
        return 1
    fi
    
    # Validate value based on key
    case "$key" in
        threefold.mnemonic|mnemonic)
            if ! validate_mnemonic "$value"; then
                log_error "Invalid mnemonic format. Expected 12 words"
                return 1
            fi
            # Update mnemonic in file
            sed -i "s|mnemonic: \".*\"|mnemonic: \"$value\"|" "$CREDENTIALS_FILE"
            log_success "Mnemonic updated"
            ;;
        github.token|github-token)
            # Add or update GitHub section
            if grep -q "^github:" "$CREDENTIALS_FILE"; then
                sed -i "/^github:/,/^$/s|token: \".*\"|token: \"$value\"|" "$CREDENTIALS_FILE"
            else
                echo "" >> "$CREDENTIALS_FILE"
                echo "github:" >> "$CREDENTIALS_FILE"
                echo "  token: \"$value\"" >> "$CREDENTIALS_FILE"
            fi
            log_success "GitHub token updated"
            ;;
        gitea.url|gitea-url)
            # Add or update Gitea URL
            if grep -q "^gitea:" "$CREDENTIALS_FILE"; then
                sed -i "/^gitea:/,/^$/s|url: \".*\"|url: \"$value\"|" "$CREDENTIALS_FILE"
            else
                echo "" >> "$CREDENTIALS_FILE"
                echo "gitea:" >> "$CREDENTIALS_FILE"
                echo "  url: \"$value\"" >> "$CREDENTIALS_FILE"
            fi
            log_success "Gitea URL updated"
            ;;
        gitea.token|gitea-token)
            # Add or update Gitea token
            if grep -q "^gitea:" "$CREDENTIALS_FILE"; then
                if grep -q "token:" "$CREDENTIALS_FILE" | grep -A2 "gitea:"; then
                    sed -i "/^gitea:/,/^$/s|token: \".*\"|token: \"$value\"|" "$CREDENTIALS_FILE"
                else
                    sed -i "/^gitea:/a\\  token: \"$value\"" "$CREDENTIALS_FILE"
                fi
            else
                echo "" >> "$CREDENTIALS_FILE"
                echo "gitea:" >> "$CREDENTIALS_FILE"
                echo "  url: \"https://git.ourworld.tf\"" >> "$CREDENTIALS_FILE"
                echo "  token: \"$value\"" >> "$CREDENTIALS_FILE"
            fi
            log_success "Gitea token updated"
            ;;
        *)
            log_error "Unknown key: $key"
            echo ""
            echo "Valid keys:"
            echo "  threefold.mnemonic (or mnemonic)"
            echo "  github.token (or github-token)"
            echo "  gitea.url (or gitea-url)"
            echo "  gitea.token (or gitea-token)"
            return 1
            ;;
    esac
}

# Delete config value
config_delete() {
    local key="$1"
    
    if [ -z "$key" ]; then
        echo ""
        log_error "Key is required"
        echo ""
        echo "Usage:"
        echo "  tfgrid-compose config delete <key>"
        echo ""
        echo "Examples:"
        echo "  tfgrid-compose config delete github-token"
        echo "  tfgrid-compose config delete gitea-token"
        echo ""
        return 1
    fi
    
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        log_error "No credentials found"
        return 1
    fi
    
    # Prevent deleting required mnemonic
    if [ "$key" = "threefold.mnemonic" ] || [ "$key" = "mnemonic" ]; then
        echo ""
        log_error "Cannot delete mnemonic"
        echo ""
        echo "The mnemonic is required for deployments."
        echo "To remove all credentials, use:"
        echo "  tfgrid-compose logout"
        echo ""
        return 1
    fi
    
    echo ""
    echo -n "Delete $key? (yes/no): "
    read -r confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        return 0
    fi
    
    case "$key" in
        github.token|github-token)
            sed -i '/^github:/,/^$/d' "$CREDENTIALS_FILE"
            log_success "GitHub token deleted"
            ;;
        gitea.url|gitea-url|gitea.token|gitea-token)
            sed -i '/^gitea:/,/^$/d' "$CREDENTIALS_FILE"
            log_success "Gitea configuration deleted"
            ;;
        *)
            log_error "Unknown key: $key"
            return 1
            ;;
    esac
}

# Config command dispatcher
cmd_config() {
    local subcommand="$1"
    shift || true
    
    case "$subcommand" in
        list)
            config_list
            ;;
        get)
            config_get "$@"
            ;;
        set)
            config_set "$@"
            ;;
        delete)
            config_delete "$@"
            ;;
        *)
            echo "Usage: tfgrid-compose config <subcommand>"
            echo ""
            echo "Subcommands:"
            echo "  list              List all configuration (masks sensitive values)"
            echo "  get <key>         Get specific configuration value"
            echo "  set <key> <value> Set configuration value"
            echo "  delete <key>      Delete configuration value"
            echo ""
            echo "Examples:"
            echo "  tfgrid-compose config list"
            echo "  tfgrid-compose config get github-token"
            echo "  tfgrid-compose config set github-token ghp_abc123"
            echo "  tfgrid-compose config delete github-token"
            return 1
            ;;
    esac
}
