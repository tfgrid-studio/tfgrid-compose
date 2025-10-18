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
    local mnemonic=""
    local attempts=0
    local max_attempts=3
    
    echo "" >&2
    echo "ThreeFold Mnemonic (required):" >&2
    echo "  This is your seed phrase from your ThreeFold Chain wallet" >&2
    echo "  ℹ  Need help? See: tfgrid-compose docs" >&2
    
    while [ $attempts -lt $max_attempts ]; do
        echo "" >&2
        echo "→ Enter mnemonic (12 or 24 words):" >&2
        echo "  (input hidden for security)" >&2
        echo -n "  " >&2
        read -s -r mnemonic
        echo "" >&2  # New line after hidden input
        
        # Check if empty
        if [ -z "$mnemonic" ]; then
            attempts=$((attempts + 1))
            echo "" >&2
            log_error "Mnemonic cannot be empty"
            echo "" >&2
            if [ $attempts -lt $max_attempts ]; then
                echo "Try again ($attempts/$max_attempts attempts used)" >&2
                continue
            else
                echo "Maximum attempts reached." >&2
                echo "" >&2
                echo "Need help getting started?" >&2
                echo "  → tfgrid-compose docs" >&2
                echo "  → https://docs.tfgrid.studio/getting-started/threefold-setup" >&2
                echo "" >&2
                return 1
            fi
        fi
        
        # Validate word count
        if ! validate_mnemonic "$mnemonic"; then
            attempts=$((attempts + 1))
            local word_count=$(echo "$mnemonic" | wc -w | tr -d ' ')
            echo "" >&2
            log_error "Invalid seed phrase format" >&2
            echo "" >&2
            echo "Expected: 12 or 24 words" >&2
            echo "Got: $word_count words" >&2
            echo "" >&2
            if [ $attempts -lt $max_attempts ]; then
                echo "Try again ($attempts/$max_attempts attempts used)" >&2
                continue
            else
                echo "Maximum attempts reached." >&2
                echo "" >&2
                echo "Each word should be separated by spaces." >&2
                echo "Run 'tfgrid-compose login' again when ready." >&2
                echo "" >&2
                return 1
            fi
        fi
        
        # Success!
        local word_count=$(echo "$mnemonic" | wc -w | tr -d ' ')
        echo "" >&2
        log_success "Validated: $word_count words" >&2
        echo "" >&2
        echo "$mnemonic"
        return 0
    done
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
    echo "→ GitHub token:" >&2
    echo "  (input hidden for security)" >&2
    echo -n "  " >&2
    read -s -r token
    echo "" >&2  # New line after hidden input
    
    # Skip validation if empty (optional)
    if [ -z "$token" ]; then
        echo "" >&2
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
        echo "  (input hidden for security)" >&2
        echo -n "  " >&2
        read -s -r token
        echo "" >&2
        
        # If still invalid after retry, skip it
        if [ -n "$token" ] && ! validate_github_token "$token"; then
            echo "" >&2
            log_warning "Invalid token format, skipping..." >&2
            token=""
        fi
    fi
    
    if [ -n "$token" ]; then
        echo "" >&2
        log_success "GitHub token configured" >&2
        echo "" >&2
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
    echo "→ Gitea token:" >&2
    echo "  (input hidden for security)" >&2
    echo -n "  " >&2
    read -s -r token
    echo "" >&2  # New line after hidden input
    
    if [ -n "$token" ]; then
        echo "" >&2
        log_success "Gitea token configured" >&2
        echo "" >&2
    fi
    
    echo "$token"
}

# Validate git name (basic check)
validate_git_name() {
    local name="$1"
    
    # Not empty and reasonable length
    if [ -z "$name" ] || [ ${#name} -lt 2 ]; then
        return 1
    fi
    
    return 0
}

# Validate git email
validate_git_email() {
    local email="$1"
    
    # Basic email validation
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    fi
    
    return 1
}

# Prompt for git name
prompt_git_name() {
    echo "" >&2
    echo "Git Name (for commits):" >&2
    echo "  Your full name that will appear in git commits" >&2
    echo "  ℹ  Example: John Doe" >&2
    echo "" >&2
    
    local name=""
    while [ -z "$name" ]; do
        echo -n "→ Git name: " >&2
        read -r name
        
        if [ -z "$name" ]; then
            echo "" >&2
            log_error "Name cannot be empty"
            echo "" >&2
        elif ! validate_git_name "$name"; then
            echo "" >&2
            log_error "Name too short (minimum 2 characters)"
            echo "" >&2
            name=""
        fi
    done
    
    echo "" >&2
    log_success "Git name set: $name" >&2
    echo "" >&2
    echo "$name"
}

# Prompt for git email
prompt_git_email() {
    echo "" >&2
    echo "Git Email (for commits):" >&2
    echo "  Your email that will appear in git commits" >&2
    echo "  ℹ  Example: john@example.com" >&2
    echo "" >&2
    
    local email=""
    local attempts=0
    local max_attempts=3
    
    while [ $attempts -lt $max_attempts ]; do
        echo -n "→ Git email: " >&2
        read -r email
        
        if [ -z "$email" ]; then
            attempts=$((attempts + 1))
            echo "" >&2
            log_error "Email cannot be empty"
            echo "" >&2
            if [ $attempts -lt $max_attempts ]; then
                echo "Try again ($attempts/$max_attempts attempts used)" >&2
                continue
            else
                echo "Maximum attempts reached." >&2
                return 1
            fi
        fi
        
        if ! validate_git_email "$email"; then
            attempts=$((attempts + 1))
            echo "" >&2
            log_error "Invalid email format"
            echo "" >&2
            if [ $attempts -lt $max_attempts ]; then
                echo "Expected format: user@domain.com" >&2
                echo "Try again ($attempts/$max_attempts attempts used)" >&2
                continue
            else
                echo "Maximum attempts reached." >&2
                return 1
            fi
        fi
        
        # Success!
        echo "" >&2
        log_success "Git email set: $email" >&2
        echo "" >&2
        echo "$email"
        return 0
    done
    
    return 1
}

# Save credentials to file
save_credentials() {
    local mnemonic="$1"
    local github_token="$2"
    local gitea_url="$3"
    local gitea_token="$4"
    local git_name="$5"
    local git_email="$6"
    
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
    
    # Add git identity if provided
    if [ -n "$git_name" ] || [ -n "$git_email" ]; then
        cat >> "$CREDENTIALS_FILE" << EOF
git:
EOF
        if [ -n "$git_name" ]; then
            echo "  name: \"$git_name\"" >> "$CREDENTIALS_FILE"
        fi
        if [ -n "$git_email" ]; then
            echo "  email: \"$git_email\"" >> "$CREDENTIALS_FILE"
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
    # Note: This is a simple YAML parser
    
    # Get mnemonic (under threefold section)
    export TFGRID_MNEMONIC=$(grep "mnemonic:" "$CREDENTIALS_FILE" | sed 's/.*mnemonic: "\(.*\)"/\1/')
    
    # Get GitHub token (under github section)
    export TFGRID_GITHUB_TOKEN=$(awk '/^github:/{flag=1; next} /^[a-z]/{flag=0} flag && /token:/{print; exit}' "$CREDENTIALS_FILE" | sed 's/.*token: "\(.*\)"/\1/')
    
    # Get Gitea URL (under gitea section)
    export TFGRID_GITEA_URL=$(awk '/^gitea:/{flag=1; next} /^[a-z]/{flag=0} flag && /url:/{print; exit}' "$CREDENTIALS_FILE" | sed 's/.*url: "\(.*\)"/\1/')
    
    # Get Gitea token (under gitea section)
    export TFGRID_GITEA_TOKEN=$(awk '/^gitea:/{flag=1; next} /^[a-z]/{flag=0} flag && /token:/{print; exit}' "$CREDENTIALS_FILE" | sed 's/.*token: "\(.*\)"/\1/')
    
    # Get git name (under git section)
    export TFGRID_GIT_NAME=$(awk '/^git:/{flag=1; next} /^[a-z]/{flag=0} flag && /name:/{print; exit}' "$CREDENTIALS_FILE" | sed 's/.*name: "\(.*\)"/\1/')
    
    # Get git email (under git section)
    export TFGRID_GIT_EMAIL=$(awk '/^git:/{flag=1; next} /^[a-z]/{flag=0} flag && /email:/{print; exit}' "$CREDENTIALS_FILE" | sed 's/.*email: "\(.*\)"/\1/')
    
    return 0
}

# Show credential status
show_credential_status() {
    echo "Current credentials:"
    
    if [ -n "$TFGRID_MNEMONIC" ]; then
        local word_count=$(echo "$TFGRID_MNEMONIC" | wc -w | tr -d ' ')
        echo "  ✓ Mnemonic:     ********** ($word_count words)"
    else
        echo "  ✗ Mnemonic:     (not set)"
    fi
    
    if [ -n "$TFGRID_GITHUB_TOKEN" ]; then
        echo "  ✓ GitHub token: ********** (configured)"
    else
        echo "  ✗ GitHub token: (not set)"
    fi
    
    if [ -n "$TFGRID_GITEA_URL" ]; then
        echo "  ✓ Gitea URL:    $TFGRID_GITEA_URL"
    else
        echo "  ✗ Gitea URL:    (not set)"
    fi
    
    if [ -n "$TFGRID_GITEA_TOKEN" ]; then
        echo "  ✓ Gitea token:  ********** (configured)"
    else
        echo "  ✗ Gitea token:  (not set)"
    fi
    
    if [ -n "$TFGRID_GIT_NAME" ]; then
        echo "  ✓ Git name:     $TFGRID_GIT_NAME"
    else
        echo "  ✗ Git name:     (not set)"
    fi
    
    if [ -n "$TFGRID_GIT_EMAIL" ]; then
        echo "  ✓ Git email:    $TFGRID_GIT_EMAIL"
    else
        echo "  ✗ Git email:    (not set)"
    fi
}

# Add only missing credentials
add_missing_credentials() {
    local updated=false
    local git_name="$TFGRID_GIT_NAME"
    local git_email="$TFGRID_GIT_EMAIL"
    
    echo ""
    log_info "Adding missing credentials..."
    echo ""
    
    # Check git name
    if [ -z "$TFGRID_GIT_NAME" ]; then
        if git_name=$(prompt_git_name); then
            updated=true
        else
            log_error "Failed to set git name"
            return 1
        fi
    else
        echo "Git name already set: $TFGRID_GIT_NAME"
        echo ""
    fi
    
    # Check git email
    if [ -z "$TFGRID_GIT_EMAIL" ]; then
        if git_email=$(prompt_git_email); then
            updated=true
        else
            log_error "Failed to set git email"
            return 1
        fi
    else
        echo "Git email already set: $TFGRID_GIT_EMAIL"
        echo ""
    fi
    
    if [ "$updated" = true ]; then
        # Re-save credentials with new git info
        save_credentials "$TFGRID_MNEMONIC" "$TFGRID_GITHUB_TOKEN" "$TFGRID_GITEA_URL" "$TFGRID_GITEA_TOKEN" "$git_name" "$git_email"
        echo ""
        log_success "✅ Git credentials added!"
        echo ""
    else
        echo ""
        log_info "All credentials already configured"
        echo ""
    fi
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
    
    # Check git identity
    if [ -n "$TFGRID_GIT_NAME" ]; then
        echo "✓ Git name: $TFGRID_GIT_NAME"
    else
        echo "⊘ Git name: Not configured (recommended for commits)"
    fi
    
    if [ -n "$TFGRID_GIT_EMAIL" ]; then
        echo "✓ Git email: $TFGRID_GIT_EMAIL"
    else
        echo "⊘ Git email: Not configured (recommended for commits)"
    fi
    
    echo ""
    log_success "Credentials valid! ✅"
    
    # Show helpful message if git identity is missing
    if [ -z "$TFGRID_GIT_NAME" ] || [ -z "$TFGRID_GIT_EMAIL" ]; then
        echo ""
        log_info "💡 Tip: Add git identity for better commit attribution"
        echo "  Run: tfgrid-compose login"
        echo "  (Select option 1 to add missing credentials)"
    fi
    
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
        log_info "You are already logged in."
        echo ""
        
        # Load and show current credentials
        load_credentials
        show_credential_status
        
        echo ""
        echo "What would you like to do?"
        echo "  1) Add missing credentials (recommended)"
        echo "  2) Update all credentials (re-enter everything)"
        echo "  3) Check credentials and exit"
        echo ""
        
        read -p "Choice [1-3]: " choice
        choice=${choice:-1}  # Default to 1
        
        case $choice in
            1)
                # Add missing only
                add_missing_credentials
                return $?
                ;;
            2)
                # Update all - ask for confirmation
                echo ""
                log_warning "This will re-enter all credentials."
                echo ""
                read -p "Continue? (yes/no): " confirm
                if [ "$confirm" != "yes" ]; then
                    echo "Cancelled"
                    return 0
                fi
                # Fall through to normal login flow below
                ;;
            3)
                # Just check
                echo ""
                check_credentials
                return $?
                ;;
            *)
                echo ""
                log_info "Cancelled"
                return 0
                ;;
        esac
    fi
    
    # Welcome message (first-time or update-all)
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
    
    # Prompt for git identity
    local git_name
    if ! git_name=$(prompt_git_name); then
        log_warning "Skipping git name (you can add it later with: tfgrid-compose login)"
        git_name=""
    fi
    
    local git_email
    if ! git_email=$(prompt_git_email); then
        log_warning "Skipping git email (you can add it later with: tfgrid-compose login)"
        git_email=""
    fi
    
    # Save credentials
    save_credentials "$mnemonic" "$github_token" "$gitea_url" "$gitea_token" "$git_name" "$git_email"
    
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
