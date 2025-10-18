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

# Git config commands
config_gitconfig() {
    local context=""
    local show_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --context=*)
                context="${1#*=}"
                shift
                ;;
            --context)
                context="$2"
                shift 2
                ;;
            --show)
                show_only=true
                shift
                ;;
            --help|-h)
                echo ""
                echo "Git Configuration for TFGrid Compose"
                echo ""
                echo "USAGE:"
                echo "  tfgrid-compose config gitconfig                    # Set default git config"
                echo "  tfgrid-compose config gitconfig --context=github   # Set GitHub-specific config"
                echo "  tfgrid-compose config gitconfig --context=gitea    # Set Gitea-specific config"
                echo "  tfgrid-compose config gitconfig --context=tfgrid-ai-agent  # Set AI agent config"
                echo "  tfgrid-compose config gitconfig --show             # Show current config"
                echo ""
                echo "CONTEXTS:"
                echo "  github          - For ~/code/github.com/ repos"
                echo "  gitea           - For ~/code/tfgrid-gitea/ repos"
                echo "  tfgrid-ai-agent - For ~/code/tfgrid-ai-agent-projects/ repos"
                echo ""
                echo "Git automatically uses the appropriate identity based on repository location."
                echo ""
                return 0
                ;;
            *)
                echo ""
                log_error "Unknown option: $1"
                echo ""
                echo "Run 'tfgrid-compose config gitconfig --help' for usage"
                echo ""
                return 1
                ;;
        esac
    done

    # Check git availability
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed"
        return 1
    fi

    # Show current config if requested
    if [ "$show_only" = true ]; then
        show_current_git_config
        return 0
    fi

    # If no arguments provided, show help
    if [ $# -eq 0 ] && [ -z "$context" ]; then
        echo ""
        echo "Git Configuration for TFGrid Compose"
        echo ""
        echo "USAGE:"
        echo "  tfgrid-compose config gitconfig                    # Set default git config"
        echo "  tfgrid-compose config gitconfig --context=github   # Set GitHub-specific config"
        echo "  tfgrid-compose config gitconfig --context=gitea    # Set Gitea-specific config"
        echo "  tfgrid-compose config gitconfig --context=tfgrid-ai-agent  # Set AI agent config"
        echo "  tfgrid-compose config gitconfig --show             # Show current config"
        echo ""
        echo "CONTEXTS:"
        echo "  github          - For ~/code/github.com/ repos"
        echo "  gitea           - For ~/code/tfgrid-gitea/ repos"
        echo "  tfgrid-ai-agent - For ~/code/tfgrid-ai-agent-projects/ repos"
        echo ""
        echo "Git automatically uses the appropriate identity based on repository location."
        echo ""
        return 0
    fi

    # Determine context description
    local context_desc=""
    case "$context" in
        github)
            context_desc="GitHub repositories"
            ;;
        gitea)
            context_desc="Gitea repositories"
            ;;
        tfgrid-ai-agent)
            context_desc="AI Agent projects"
            ;;
        *)
            if [ -n "$context" ]; then
                context_desc="$context repositories"
            else
                context_desc="default/global"
            fi
            ;;
    esac

    echo ""
    log_info "TFGrid Compose - Git Configuration"
    echo ""

    # Prompt for identity
    local identity
    if ! identity=$(prompt_git_identity "$context" "$context_desc"); then
        return 1
    fi

    # Parse identity
    IFS='|' read -r name email <<< "$identity"

    # Set config
    set_git_config "$context" "$name" "$email"

    echo ""
    echo "✅ Git identity configured for $context_desc"
    echo ""
    echo "Name:  $name"
    echo "Email: $email"
    echo ""

    if [ -z "$name" ] || [ -z "$email" ]; then
        echo "⚠️  Warning: Empty values detected. Please check your input."
        echo ""
    fi

    if [ -n "$context" ]; then
        echo "This identity will be used for repositories in:"
        echo "  ~/code/$context/"
        echo ""
    else
        echo "This is your default/global git identity"
        echo ""
    fi

    echo "You can set additional contexts:"
    echo "  tfgrid-compose config gitconfig --context=github"
    echo "  tfgrid-compose config gitconfig --context=gitea"
    echo "  tfgrid-compose config gitconfig --context=tfgrid-ai-agent"
    echo ""
}

# Show current git config
show_current_git_config() {
    echo ""
    echo "📋 Current Git Configuration:"
    echo ""

    local global_name=$(git config --global user.name 2>/dev/null || echo "")
    local global_email=$(git config --global user.email 2>/dev/null || echo "")

    if [ -n "$global_name" ] || [ -n "$global_email" ]; then
        echo "Global config:"
        [ -n "$global_name" ] && echo "  Name:  $global_name"
        [ -n "$global_email" ] && echo "  Email: $global_email"
        echo ""
    else
        echo "No global git config set"
        echo ""
    fi

    # Show conditional includes if any
    local gitconfig="$HOME/.gitconfig"
    if [ -f "$gitconfig" ]; then
        echo "Conditional includes:"
        grep -A 1 "includeIf" "$gitconfig" 2>/dev/null | while read -r line; do
            if [[ "$line" =~ includeIf.*gitdir:(.*) ]]; then
                local path="${BASH_REMATCH[1]}"
                echo "  $path"
            fi
        done
        echo ""
    fi
}

# Validate email format
validate_email() {
    local email="$1"
    # Basic email validation
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    return 1
}

# Prompt for git identity
prompt_git_identity() {
    local context="$1"
    local context_desc="$2"

    echo ""
    if [ -n "$context" ]; then
        echo "👤 Git Identity for $context_desc:"
    else
        echo "👤 Git Identity (Default):"
    fi
    echo ""

    # Get current values if they exist
    local current_name=""
    local current_email=""

    if [ -n "$context" ]; then
        # Check if context config exists
        local context_file="$HOME/.gitconfig-$context"
        if [ -f "$context_file" ]; then
            current_name=$(git config --file "$context_file" user.name 2>/dev/null || echo "")
            current_email=$(git config --file "$context_file" user.email 2>/dev/null || echo "")
        fi
    else
        current_name=$(git config --global user.name 2>/dev/null || echo "")
        current_email=$(git config --global user.email 2>/dev/null || echo "")
    fi

    # Show current values
    if [ -n "$current_name" ] || [ -n "$current_email" ]; then
        echo "Current config:"
        [ -n "$current_name" ] && echo "  Name:  $current_name"
        [ -n "$current_email" ] && echo "  Email: $current_email"
        echo ""
        echo -n "Use existing config? (Y/n): "
        read -r use_existing
        use_existing=${use_existing:-Y}

        if [[ "$use_existing" =~ ^[Yy]$ ]]; then
            echo "$current_name|$current_email"
            return 0
        fi
    else
        echo "No current config found for this context."
        echo ""
    fi

    # Prompt for new values
    local name=""
    local email=""

    echo "Please enter your git identity information:"
    echo ""

    while [ -z "$name" ]; do
        echo -n "Enter name: "
        read -r name
        if [ -z "$name" ]; then
            echo "Name cannot be empty"
        fi
    done

    while [ -z "$email" ]; do
        echo -n "Enter email: "
        read -r email
        if [ -z "$email" ]; then
            echo "Email cannot be empty"
        elif ! validate_email "$email"; then
            echo "Invalid email format"
            email=""
        fi
    done

    echo "$name|$email"
}

# Set git config for context
set_git_config() {
    local context="$1"
    local name="$2"
    local email="$3"

    if [ -n "$context" ]; then
        # Context-specific config
        local config_file="$HOME/.gitconfig-$context"

        git config --file "$config_file" user.name "$name"
        git config --file "$config_file" user.email "$email"

        # Ensure conditional include exists in main config
        local gitconfig="$HOME/.gitconfig"
        local include_pattern="gitdir:$HOME/code/$context/"

        if ! grep -q "$include_pattern" "$gitconfig" 2>/dev/null; then
            echo "[includeIf \"gitdir:$HOME/code/$context/\"]" >> "$gitconfig"
            echo "    path = ~/.gitconfig-$context" >> "$gitconfig"
            echo "" >> "$gitconfig"
        fi

        log_success "Git config set for $context context"
    else
        # Global config
        git config --global user.name "$name"
        git config --global user.email "$email"
        log_success "Global git config set"
    fi
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
        gitconfig)
            config_gitconfig "$@"
            ;;
        git-identity|gitidentity)
            config_gitconfig "$@"
            ;;
        *)
            echo "Usage: tfgrid-compose config <subcommand>"
            echo ""
            echo "Subcommands:"
            echo "  list              List all configuration (masks sensitive values)"
            echo "  get <key>         Get specific configuration value"
            echo "  set <key> <value> Set configuration value"
            echo "  delete <key>      Delete configuration value"
            echo "  gitconfig         Configure git identity (context-aware)"
            echo "  git-identity      Alias for gitconfig"
            echo ""
            echo "Examples:"
            echo "  tfgrid-compose config list"
            echo "  tfgrid-compose config get github-token"
            echo "  tfgrid-compose config set github-token ghp_abc123"
            echo "  tfgrid-compose config delete github-token"
            echo "  tfgrid-compose config gitconfig --context=github"
            echo "  tfgrid-compose config git-identity --context=github"
            return 1
            ;;
    esac
}
