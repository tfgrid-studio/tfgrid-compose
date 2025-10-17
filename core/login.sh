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

# Validate mnemonic format (12 or 24 words)
validate_mnemonic() {
    local mnemonic="$1"
    local word_count=$(echo "$mnemonic" | wc -w | tr -d ' ')
    
    if [ "$word_count" -ne 12 ] && [ "$word_count" -ne 24 ]; then
        return 1
    fi
    return 0
}

# Prompt for mnemonic
prompt_mnemonic() {
    echo "" >&2
    echo "ThreeFold Mnemonic (required):" >&2
    echo "  This is your seed phrase from your ThreeFold Chain wallet" >&2
    echo "  ℹ  Need help? See: tfgrid-compose docs" >&2
    echo "" >&2
    echo -n "→ Enter mnemonic: " >&2
    read -r mnemonic
    
    if [ -z "$mnemonic" ]; then
        echo "" >&2
        log_error "Mnemonic is required to deploy on ThreeFold Grid"
        echo "" >&2
        echo "Need help getting started?" >&2
        echo "  → tfgrid-compose docs" >&2
        echo "  → https://docs.tfgrid.studio/getting-started/threefold-setup" >&2
        echo "" >&2
        return 1
    fi
    
    if ! validate_mnemonic "$mnemonic"; then
        local word_count=$(echo "$mnemonic" | wc -w | tr -d ' ')
        echo "" >&2
        log_error "Invalid seed phrase format" >&2
        echo "" >&2
        echo "Expected: 12 or 24 words" >&2
        echo "Got: $word_count words" >&2
        echo "" >&2
        echo "Check your seed phrase and try again." >&2
        echo "Each word should be separated by spaces." >&2
        echo "" >&2
        return 1
    fi
    
    echo "$mnemonic"
}

# Validate GitHub token format (basic check)
validate_github_token() {
    local token="$1"
    
    # Empty is OK (optional)
    if [ -z "$token" ]; then
        return 0
    fi
    
    # GitHub tokens should not have spaces
    if [[ "$token" =~ [[:space:]] ]]; then
        return 1
    fi
    
    # GitHub tokens are typically 40+ characters
    if [ ${#token} -lt 20 ]; then
        return 1
    fi
    
    return 0
}

# Prompt for GitHub token
prompt_github_token() {
    echo "" >&2
    echo "GitHub Token (optional):" >&2
    echo "  Required for deploying from private GitHub repositories" >&2
    echo "  ℹ  Create at: https://github.com/settings/tokens" >&2
    echo "  ℹ  Press Enter to skip" >&2
    echo "" >&2
    echo -n "→ GitHub token: " >&2
    read -r token
    
    # Skip validation if empty (optional)
    if [ -z "$token" ]; then
        echo ""
        return 0
    fi
    
    # Validate token format
    if ! validate_github_token "$token"; then
        echo "" >&2
        log_error "Invalid GitHub token format" >&2
        echo "" >&2
        echo "GitHub tokens should:" >&2
        echo "  - Be at least 20 characters long" >&2
        echo "  - Not contain spaces" >&2
        echo "" >&2
        echo "Press Enter to skip, or paste a valid token:" >&2
        echo -n "→ GitHub token: " >&2
        read -r token
        
        # If still invalid after retry, skip it
        if [ -n "$token" ] && ! validate_github_token "$token"; then
            echo "" >&2
            log_warning "Invalid token format, skipping..." >&2
            token=""
        fi
    fi
    
    echo "$token"
}

# Prompt for Gitea URL
prompt_gitea_url() {
    echo "" >&2
    echo "Gitea URL (optional):" >&2
    echo "  Default: https://git.ourworld.tf" >&2
    echo "  ℹ  Press Enter to use default" >&2
    echo "" >&2
    echo -n "→ Gitea URL: " >&2
    read -r url
    
    if [ -z "$url" ]; then
        echo "https://git.ourworld.tf"
    else
        echo "$url"
    fi
}

# Prompt for Gitea token
prompt_gitea_token() {
    echo "" >&2
    echo "Gitea Token (optional):" >&2
    echo "  Required for deploying from private Gitea repositories" >&2
    echo "  ℹ  Press Enter to skip" >&2
    echo "" >&2
    echo -n "→ Gitea token: " >&2
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
    
    # Add Gitea config (always add if URL or token is set)
    if [ -n "$gitea_url" ] || [ -n "$gitea_token" ]; then
        # Use default URL if not provided
        local final_gitea_url="${gitea_url:-https://git.ourworld.tf}"
        
        cat >> "$CREDENTIALS_FILE" << EOF
gitea:
  url: "$final_gitea_url"
EOF
        if [ -n "$gitea_token" ]; then
            echo "  token: \"$gitea_token\"" >> "$CREDENTIALS_FILE"
        fi
        echo "" >> "$CREDENTIALS_FILE"
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

check_credentials() {
    if ! is_logged_in; then
        echo ""
        log_error "No credentials configured"
        echo ""
        echo "You need to login first:"
        echo "  tfgrid-compose login"
        echo ""
        echo "Need help? See the setup guide:"
        echo "  → tfgrid-compose docs"
        echo ""
        return 1
    fi
    load_credentials
    
    echo ""
    log_info "Checking credentials..."
    echo ""
    
    # Check mnemonic
    if [ -n "$TFGRID_MNEMONIC" ]; then
        if validate_mnemonic "$TFGRID_MNEMONIC"; then
            local word_count=$(echo "$TFGRID_MNEMONIC" | wc -w | tr -d ' ')
            echo "✓ Mnemonic: Valid ($word_count words)"
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
                echo ""
                log_error "Unknown option: $1"
                echo ""
                echo "Usage:"
                echo "  tfgrid-compose login          # Interactive login"
                echo "  tfgrid-compose login --check  # Check credentials"
                echo ""
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
    
    # Prompt for credentials (with proper error handling)
    local mnemonic
    if ! mnemonic=$(prompt_mnemonic); then
        return 1
    fi
    
    local github_token
    github_token=$(prompt_github_token)
    
    local gitea_url
    gitea_url=$(prompt_gitea_url)
    
    local gitea_token=""
    # Only prompt for Gitea token if URL was provided (even if default)
    gitea_token=$(prompt_gitea_token)
    
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
