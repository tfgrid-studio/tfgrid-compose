#!/usr/bin/env bash
# TFGrid Compose - Login Module
# Handles interactive credential setup

# Credentials file location
CREDENTIALS_FILE="$HOME/.config/tfgrid-compose/credentials.yaml"

# Ensure credentials directory exists
ensure_credentials_dir() {
    mkdir -p "$(dirname "$CREDENTIALS_FILE")"
}

# Check if already logged in
is_logged_in() {
    [ -f "$CREDENTIALS_FILE" ] && [ -s "$CREDENTIALS_FILE" ]
}

# Validate mnemonic format (12 words)
validate_mnemonic() {
    local mnemonic="$1"
    local word_count=$(echo "$mnemonic" | wc -w | tr -d ' ')
    
    if [ "$word_count" -ne 12 ]; then
        return 1
    fi
    return 0
}

# Prompt for mnemonic
prompt_mnemonic() {
    echo ""
    echo "ThreeFold Mnemonic (required):"
    echo "  This is your 12-word secret phrase from your ThreeFold wallet"
    echo "  ℹ  Need help? Visit: https://manual.grid.tf/"
    echo ""
    echo -n "→ Enter mnemonic: "
    read -r mnemonic
    
    if [ -z "$mnemonic" ]; then
        log_error "Mnemonic is required"
        return 1
    fi
    
    if ! validate_mnemonic "$mnemonic"; then
        log_error "Invalid mnemonic format. Expected 12 words, got $(echo "$mnemonic" | wc -w | tr -d ' ')"
        return 1
    fi
    
    echo "$mnemonic"
}

# Prompt for GitHub token
prompt_github_token() {
    echo ""
    echo "GitHub Token (optional):"
    echo "  Required for deploying from private GitHub repositories"
    echo "  ℹ  Create at: https://github.com/settings/tokens"
    echo "  ℹ  Press Enter to skip"
    echo ""
    echo -n "→ GitHub token: "
    read -r token
    
    echo "$token"
}

# Prompt for Gitea URL
prompt_gitea_url() {
    echo ""
    echo "Gitea URL (optional):"
    echo "  Default: https://git.ourworld.tf"
    echo "  ℹ  Press Enter to use default"
    echo ""
    echo -n "→ Gitea URL: "
    read -r url
    
    if [ -z "$url" ]; then
        echo "https://git.ourworld.tf"
    else
        echo "$url"
    fi
}

# Prompt for Gitea token
prompt_gitea_token() {
    echo ""
    echo "Gitea Token (optional):"
    echo "  Required for deploying from private Gitea repositories"
    echo "  ℹ  Press Enter to skip"
    echo ""
    echo -n "→ Gitea token: "
    read -r token
    
    echo "$token"
}

# Save credentials to file
save_credentials() {
    local mnemonic="$1"
    local github_token="$2"
    local gitea_url="$3"
    local gitea_token="$4"
    
    ensure_credentials_dir
    
    # Create YAML file
    cat > "$CREDENTIALS_FILE" << EOF
# TFGrid Compose Credentials
# Generated: $(date)

threefold:
  mnemonic: "$mnemonic"

EOF
    
    # Add GitHub token if provided
    if [ -n "$github_token" ]; then
        cat >> "$CREDENTIALS_FILE" << EOF
github:
  token: "$github_token"

EOF
    fi
    
    # Add Gitea config if URL provided
    if [ -n "$gitea_url" ] && [ "$gitea_url" != "https://git.ourworld.tf" ]; then
        cat >> "$CREDENTIALS_FILE" << EOF
gitea:
  url: "$gitea_url"
EOF
        if [ -n "$gitea_token" ]; then
            echo "  token: \"$gitea_token\"" >> "$CREDENTIALS_FILE"
        fi
        echo "" >> "$CREDENTIALS_FILE"
    elif [ -n "$gitea_token" ]; then
        cat >> "$CREDENTIALS_FILE" << EOF
gitea:
  url: "https://git.ourworld.tf"
  token: "$gitea_token"

EOF
    fi
    
    # Set secure permissions
    chmod 600 "$CREDENTIALS_FILE"
}

# Load credentials
load_credentials() {
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        return 1
    fi
    
    # Export credentials as environment variables
    # Note: This is a simple parser, assumes YAML structure
    export TFGRID_MNEMONIC=$(grep "mnemonic:" "$CREDENTIALS_FILE" | sed 's/.*mnemonic: "\(.*\)"/\1/')
    export TFGRID_GITHUB_TOKEN=$(grep "token:" "$CREDENTIALS_FILE" | grep -A1 "github:" | tail -1 | sed 's/.*token: "\(.*\)"/\1/')
    export TFGRID_GITEA_URL=$(grep "url:" "$CREDENTIALS_FILE" | grep -A2 "gitea:" | head -1 | sed 's/.*url: "\(.*\)"/\1/')
    export TFGRID_GITEA_TOKEN=$(grep "token:" "$CREDENTIALS_FILE" | grep -A2 "gitea:" | tail -1 | sed 's/.*token: "\(.*\)"/\1/')
    
    return 0
}

# Check credentials validity
check_credentials() {
    if ! is_logged_in; then
        log_error "No credentials found. Run: tfgrid-compose login"
        return 1
    fi
    
    load_credentials
    
    echo ""
    log_info "Checking credentials..."
    echo ""
    
    # Check mnemonic
    if [ -n "$TFGRID_MNEMONIC" ]; then
        if validate_mnemonic "$TFGRID_MNEMONIC"; then
            echo "✓ Mnemonic: Valid (12 words)"
        else
            echo "✗ Mnemonic: Invalid format"
            return 1
        fi
    else
        echo "✗ Mnemonic: Not found"
        return 1
    fi
    
    # Check GitHub token
    if [ -n "$TFGRID_GITHUB_TOKEN" ]; then
        echo "✓ GitHub token: Configured"
    else
        echo "⊘ GitHub token: Not configured (optional)"
    fi
    
    # Check Gitea
    if [ -n "$TFGRID_GITEA_URL" ]; then
        echo "✓ Gitea URL: $TFGRID_GITEA_URL"
        if [ -n "$TFGRID_GITEA_TOKEN" ]; then
            echo "✓ Gitea token: Configured"
        else
            echo "⊘ Gitea token: Not configured"
        fi
    else
        echo "⊘ Gitea: Not configured (optional)"
    fi
    
    echo ""
    log_success "Credentials valid! ✅"
    return 0
}

# Login command
cmd_login() {
    local check_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --check)
                check_only=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Usage: tfgrid-compose login [--check]"
                return 1
                ;;
        esac
    done
    
    # If --check flag, just check credentials
    if [ "$check_only" = true ]; then
        check_credentials
        return $?
    fi
    
    # Check if already logged in
    if is_logged_in; then
        echo ""
        log_warning "You are already logged in."
        echo ""
        echo "Credentials stored at: $CREDENTIALS_FILE"
        echo ""
        echo "To re-login, first logout:"
        echo "  tfgrid-compose logout"
        echo ""
        echo "To check credentials:"
        echo "  tfgrid-compose login --check"
        return 0
    fi
    
    # Welcome message
    echo ""
    log_info "Welcome to TFGrid Compose! 👋"
    echo ""
    echo "Let's set up your credentials."
    
    # Prompt for credentials
    local mnemonic=$(prompt_mnemonic)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local github_token=$(prompt_github_token)
    local gitea_url=$(prompt_gitea_url)
    local gitea_token=""
    
    if [ -n "$gitea_url" ]; then
        gitea_token=$(prompt_gitea_token)
    fi
    
    # Save credentials
    save_credentials "$mnemonic" "$github_token" "$gitea_url" "$gitea_token"
    
    echo ""
    log_success "✅ Credentials saved securely!"
    echo ""
    echo "Stored at: $CREDENTIALS_FILE"
    echo ""
    echo "You're all set! Try:"
    echo "  tfgrid-compose search"
    echo "  tfgrid-compose up single-vm"
    echo ""
}

# Logout command
cmd_logout() {
    if ! is_logged_in; then
        log_info "Not logged in"
        return 0
    fi
    
    echo ""
    log_warning "This will remove all stored credentials."
    echo ""
    echo -n "Are you sure? (yes/no): "
    read -r confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        return 0
    fi
    
    rm -f "$CREDENTIALS_FILE"
    
    echo ""
    log_success "Logged out successfully"
    echo ""
}
