#!/usr/bin/env bash
# TFGrid Compose - Login Module
# Handles interactive credential setup with multi-platform git support

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

# =============================================================================
# Multi-Platform Git Server Support
# =============================================================================

# Platform selection menu (like gits)
prompt_git_platform() {
    echo "" >&2
    echo "Git Platform Configuration:" >&2
    echo "  Configure credentials for git servers used by your deployments" >&2
    echo "" >&2
    echo "Which platform would you like to configure?" >&2
    echo "  1) Forgejo (forge.ourworld.tf)" >&2
    echo "  2) Gitea (git.ourworld.tf)" >&2
    echo "  3) GitHub (github.com)" >&2
    echo "  4) Custom server" >&2
    echo "  5) Skip git server configuration" >&2
    echo "" >&2
    echo -n "→ Choice [1-5]: " >&2
    read -r choice
    
    case "$choice" in
        1) echo "forgejo" ;;
        2) echo "gitea" ;;
        3) echo "github" ;;
        4) echo "custom" ;;
        5|"") echo "skip" ;;
        *) echo "skip" ;;
    esac
}

# Get default server for platform
get_default_server() {
    local platform="$1"
    case "$platform" in
        forgejo) echo "forge.ourworld.tf" ;;
        gitea) echo "git.ourworld.tf" ;;
        github) echo "github.com" ;;
        *) echo "" ;;
    esac
}

# Prompt for git server URL
prompt_git_server_url() {
    local platform="$1"
    local default_server=$(get_default_server "$platform")
    
    echo "" >&2
    if [ -n "$default_server" ]; then
        echo "Server URL (default: $default_server):" >&2
        echo "  ℹ  Press Enter to use default" >&2
    else
        echo "Server URL:" >&2
        echo "  ℹ  Enter the full hostname (e.g., git.example.com)" >&2
    fi
    echo "" >&2
    echo -n "→ Server: " >&2
    read -r server
    
    if [ -z "$server" ]; then
        server="$default_server"
    fi
    
    # Remove protocol if provided
    server=$(echo "$server" | sed -E 's|^https?://||' | sed 's|/$||')
    
    echo "$server"
}

# Prompt for git username
prompt_git_username() {
    local platform="$1"
    local server="$2"
    
    echo "" >&2
    echo "Username for $server (optional):" >&2
    echo "  ℹ  Used for HTTPS authentication with private repos" >&2
    echo "  ℹ  Press Enter to skip" >&2
    echo "" >&2
    echo -n "→ Username: " >&2
    read -r username
    
    echo "$username"
}

# Prompt for git token
prompt_git_token() {
    local platform="$1"
    local server="$2"
    
    echo "" >&2
    echo "API Token for $server:" >&2
    case "$platform" in
        forgejo)
            echo "  ℹ  Create at: https://$server/user/settings/applications" >&2
            ;;
        gitea)
            echo "  ℹ  Create at: https://$server/user/settings/applications" >&2
            ;;
        github)
            echo "  ℹ  Create at: https://github.com/settings/tokens" >&2
            ;;
        *)
            echo "  ℹ  Generate an API token with repo access" >&2
            ;;
    esac
    echo "  ℹ  Press Enter to skip (for public repos only)" >&2
    echo "" >&2
    echo "→ Token:" >&2
    echo "  (input hidden for security)" >&2
    echo -n "  " >&2
    read -s -r token
    echo "" >&2
    
    if [ -n "$token" ]; then
        echo "" >&2
        log_success "Token configured for $server" >&2
        echo "" >&2
    fi
    
    echo "$token"
}

# Configure a git server interactively
configure_git_server() {
    local platform=$(prompt_git_platform)
    
    if [ "$platform" = "skip" ]; then
        echo "skip"
        return 0
    fi
    
    local server=""
    local username=""
    local token=""
    
    if [ "$platform" = "github" ]; then
        server="github.com"
        # For GitHub, we might already have a token from the earlier prompt
        echo "" >&2
        echo "GitHub server: github.com" >&2
    else
        server=$(prompt_git_server_url "$platform")
        if [ -z "$server" ]; then
            echo "skip"
            return 0
        fi
        username=$(prompt_git_username "$platform" "$server")
    fi
    
    token=$(prompt_git_token "$platform" "$server")
    
    # Return the configuration as a parseable string
    echo "$platform|$server|$username|$token"
}

# =============================================================================
# Legacy Gitea Support (for backward compatibility)
# =============================================================================

# Prompt for Gitea URL (legacy - kept for backward compatibility)
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

# Prompt for Gitea token (legacy - kept for backward compatibility)
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

# =============================================================================
# Git Identity
# =============================================================================

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

# =============================================================================
# Credential Storage
# =============================================================================

# Save credentials to file (with multi-server support)
save_credentials() {
    local mnemonic="$1"
    local github_token="$2"
    local git_name="$3"
    local git_email="$4"
    shift 4
    # Remaining args are git_servers in format: "platform|server|username|token"
    local git_servers=("$@")
    
    ensure_credentials_dir
    
    # Create YAML file
    cat > "$CREDENTIALS_FILE" << EOF
# TFGrid Compose Credentials
# Generated: $(date)
# Multi-platform git support enabled

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
    
    # Add git servers (new multi-platform format)
    if [ ${#git_servers[@]} -gt 0 ]; then
        echo "git_servers:" >> "$CREDENTIALS_FILE"
        local first_server=true
        for server_config in "${git_servers[@]}"; do
            IFS='|' read -r platform server username token <<< "$server_config"
            if [ -n "$server" ] && [ "$server" != "skip" ]; then
                echo "  - name: \"$server\"" >> "$CREDENTIALS_FILE"
                echo "    platform: \"$platform\"" >> "$CREDENTIALS_FILE"
                if [ -n "$username" ]; then
                    echo "    username: \"$username\"" >> "$CREDENTIALS_FILE"
                fi
                if [ -n "$token" ]; then
                    echo "    token: \"$token\"" >> "$CREDENTIALS_FILE"
                fi
                if [ "$first_server" = true ]; then
                    echo "    default: true" >> "$CREDENTIALS_FILE"
                    first_server=false
                fi
            fi
        done
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

# Save credentials (legacy format for backward compatibility)
save_credentials_legacy() {
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

# Load credentials and export environment variables
load_credentials() {
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        return 1
    fi
    
    # Export credentials as environment variables
    
    # Get mnemonic (under threefold section)
    export TFGRID_MNEMONIC=$(grep "mnemonic:" "$CREDENTIALS_FILE" | sed 's/.*mnemonic: "\(.*\)"/\1/')
    
    # Get GitHub token (under github section)
    export TFGRID_GITHUB_TOKEN=$(awk '/^github:/{flag=1; next} /^[a-z]/{flag=0} flag && /token:/{print; exit}' "$CREDENTIALS_FILE" | sed 's/.*token: "\(.*\)"/\1/')
    
    # Get git name (under git section)
    export TFGRID_GIT_NAME=$(awk '/^git:/{flag=1; next} /^[a-z]/{flag=0} flag && /name:/{print; exit}' "$CREDENTIALS_FILE" | sed 's/.*name: "\(.*\)"/\1/')
    
    # Get git email (under git section)
    export TFGRID_GIT_EMAIL=$(awk '/^git:/{flag=1; next} /^[a-z]/{flag=0} flag && /email:/{print; exit}' "$CREDENTIALS_FILE" | sed 's/.*email: "\(.*\)"/\1/')
    
    # ==========================================================================
    # Multi-platform git server support
    # ==========================================================================
    
    # Check if new format (git_servers:) exists
    if grep -q "^git_servers:" "$CREDENTIALS_FILE" 2>/dev/null; then
        # Parse default server from git_servers section
        local default_server=""
        local default_platform=""
        local default_username=""
        local default_token=""
        
        # Find the default server (or first server)
        local in_git_servers=false
        local in_server=false
        local current_name=""
        local current_platform=""
        local current_username=""
        local current_token=""
        local current_is_default=false
        
        while IFS= read -r line; do
            if [[ "$line" =~ ^git_servers: ]]; then
                in_git_servers=true
                continue
            fi
            
            if [ "$in_git_servers" = true ]; then
                # Check for end of git_servers section
                if [[ "$line" =~ ^[a-z]+: ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
                    in_git_servers=false
                    continue
                fi
                
                # Parse server entries
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*\"(.*)\" ]]; then
                    # Save previous server if it was default
                    if [ "$current_is_default" = true ] && [ -n "$current_name" ]; then
                        default_server="$current_name"
                        default_platform="$current_platform"
                        default_username="$current_username"
                        default_token="$current_token"
                    elif [ -z "$default_server" ] && [ -n "$current_name" ]; then
                        # Use first server as default if none marked
                        default_server="$current_name"
                        default_platform="$current_platform"
                        default_username="$current_username"
                        default_token="$current_token"
                    fi
                    
                    # Start new server
                    current_name="${BASH_REMATCH[1]}"
                    current_platform=""
                    current_username=""
                    current_token=""
                    current_is_default=false
                    in_server=true
                elif [ "$in_server" = true ]; then
                    if [[ "$line" =~ platform:[[:space:]]*\"(.*)\" ]]; then
                        current_platform="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ username:[[:space:]]*\"(.*)\" ]]; then
                        current_username="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ token:[[:space:]]*\"(.*)\" ]]; then
                        current_token="${BASH_REMATCH[1]}"
                    elif [[ "$line" =~ default:[[:space:]]*true ]]; then
                        current_is_default=true
                    fi
                fi
            fi
        done < "$CREDENTIALS_FILE"
        
        # Handle last server
        if [ "$current_is_default" = true ] && [ -n "$current_name" ]; then
            default_server="$current_name"
            default_platform="$current_platform"
            default_username="$current_username"
            default_token="$current_token"
        elif [ -z "$default_server" ] && [ -n "$current_name" ]; then
            default_server="$current_name"
            default_platform="$current_platform"
            default_username="$current_username"
            default_token="$current_token"
        fi
        
        # Export generic GIT_* variables for deployments
        if [ -n "$default_server" ]; then
            export GIT_SERVER="$default_server"
            export GIT_PLATFORM="$default_platform"
            [ -n "$default_username" ] && export GIT_USERNAME="$default_username"
            [ -n "$default_token" ] && export GIT_TOKEN="$default_token"
            
            # Also export as GIT_OURWORLD_* for compatibility with existing deployments
            [ -n "$default_username" ] && export GIT_OURWORLD_USERNAME="$default_username"
            [ -n "$default_token" ] && export GIT_OURWORLD_TOKEN="$default_token"
        fi
        
        # Export platform-specific variables based on configured servers
        while IFS= read -r line; do
            if [[ "$line" =~ ^git_servers: ]]; then
                in_git_servers=true
                continue
            fi
            
            if [ "$in_git_servers" = true ]; then
                if [[ "$line" =~ ^[a-z]+: ]] && [[ ! "$line" =~ ^[[:space:]] ]]; then
                    break
                fi
                
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*\"(.*)\" ]]; then
                    current_name="${BASH_REMATCH[1]}"
                    current_platform=""
                    current_token=""
                elif [[ "$line" =~ platform:[[:space:]]*\"(.*)\" ]]; then
                    current_platform="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ token:[[:space:]]*\"(.*)\" ]]; then
                    current_token="${BASH_REMATCH[1]}"
                    
                    # Export platform-specific variables
                    case "$current_platform" in
                        forgejo)
                            export TFGRID_FORGEJO_URL="https://$current_name"
                            export TFGRID_FORGEJO_TOKEN="$current_token"
                            ;;
                        gitea)
                            export TFGRID_GITEA_URL="https://$current_name"
                            export TFGRID_GITEA_TOKEN="$current_token"
                            ;;
                    esac
                fi
            fi
        done < "$CREDENTIALS_FILE"
        
    else
        # Legacy format: gitea: section
        export TFGRID_GITEA_URL=$(awk '/^gitea:/{flag=1; next} /^[a-z]/{flag=0} flag && /url:/{print; exit}' "$CREDENTIALS_FILE" | sed 's/.*url: "\(.*\)"/\1/')
        export TFGRID_GITEA_TOKEN=$(awk '/^gitea:/{flag=1; next} /^[a-z]/{flag=0} flag && /token:/{print; exit}' "$CREDENTIALS_FILE" | sed 's/.*token: "\(.*\)"/\1/')
        
        # Also export as generic variables for compatibility
        if [ -n "$TFGRID_GITEA_URL" ]; then
            local server=$(echo "$TFGRID_GITEA_URL" | sed -E 's|^https?://||' | sed 's|/$||')
            export GIT_SERVER="$server"
            export GIT_PLATFORM="gitea"
            [ -n "$TFGRID_GITEA_TOKEN" ] && export GIT_TOKEN="$TFGRID_GITEA_TOKEN"
            [ -n "$TFGRID_GITEA_TOKEN" ] && export GIT_OURWORLD_TOKEN="$TFGRID_GITEA_TOKEN"
        fi
    fi
    
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
    
    # Show git servers (new format)
    if [ -n "$GIT_SERVER" ]; then
        echo ""
        echo "Git Servers:"
        echo "  ✓ Default:      $GIT_SERVER ($GIT_PLATFORM)"
        [ -n "$GIT_USERNAME" ] && echo "    Username:     $GIT_USERNAME"
        [ -n "$GIT_TOKEN" ] && echo "    Token:        ********** (configured)"
    fi
    
    # Show legacy gitea if no new format
    if [ -z "$GIT_SERVER" ]; then
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
    fi
    
    # Show additional platform-specific tokens
    if [ -n "$TFGRID_FORGEJO_TOKEN" ]; then
        echo "  ✓ Forgejo:      $TFGRID_FORGEJO_URL (configured)"
    fi
    
    echo ""
    echo "Git Identity:"
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
        # Re-save credentials with new git info (legacy format for compatibility)
        save_credentials_legacy "$TFGRID_MNEMONIC" "$TFGRID_GITHUB_TOKEN" "$TFGRID_GITEA_URL" "$TFGRID_GITEA_TOKEN" "$git_name" "$git_email"
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
    
    # Check git servers (new format)
    if [ -n "$GIT_SERVER" ]; then
        echo "✓ Git server: $GIT_SERVER ($GIT_PLATFORM)"
        if [ -n "$GIT_TOKEN" ]; then
            echo "✓ Git token: Configured"
        else
            echo "⊘ Git token: Not configured"
        fi
    else
        # Check Gitea (legacy)
        if [ -n "$TFGRID_GITEA_URL" ]; then
            echo "✓ Gitea URL: $TFGRID_GITEA_URL"
            if [ -n "$TFGRID_GITEA_TOKEN" ]; then
                echo "✓ Gitea token: Configured"
            else
                echo "⊘ Gitea token: Not configured"
            fi
        else
            echo "⊘ Git server: Not configured (optional)"
        fi
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

# Signin command
cmd_signin() {
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
        echo "  3) Add/update git server"
        echo "  4) Check credentials and exit"
        echo ""
        
        read -p "Choice [1-4]: " choice
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
                # Add/update git server
                echo ""
                log_info "Configure a git server..."
                local server_config=$(configure_git_server)
                if [ "$server_config" != "skip" ]; then
                    # For now, we need to re-save all credentials
                    # TODO: Implement incremental update
                    echo ""
                    log_info "Git server configuration saved. Run 'tfgrid-compose login' option 2 to fully reconfigure."
                fi
                return 0
                ;;
            4)
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
    
    # Collect git servers
    local git_servers=()
    local add_more=true
    
    echo ""
    log_info "Git Server Configuration"
    echo ""
    echo "Configure git servers for accessing repositories during deployments."
    echo "You can configure multiple servers (Forgejo, Gitea, GitHub, custom)."
    echo ""
    
    while [ "$add_more" = true ]; do
        local server_config=$(configure_git_server)
        
        if [ "$server_config" = "skip" ]; then
            add_more=false
        else
            git_servers+=("$server_config")
            
            echo ""
            echo "Add another git server?"
            echo "  1) Yes, add another"
            echo "  2) No, continue"
            echo ""
            read -p "Choice [1-2]: " add_choice
            
            if [ "$add_choice" != "1" ]; then
                add_more=false
            fi
        fi
    done
    
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
    
    # Save credentials with new format
    save_credentials "$mnemonic" "$github_token" "$git_name" "$git_email" "${git_servers[@]}"
    
    echo ""
    log_success "✅ Credentials saved securely!"
    echo ""
    echo "Stored at: $CREDENTIALS_FILE"
    echo ""
    
    # Show summary of configured servers
    if [ ${#git_servers[@]} -gt 0 ]; then
        echo "Configured git servers:"
        for server_config in "${git_servers[@]}"; do
            IFS='|' read -r platform server username token <<< "$server_config"
            echo "  • $server ($platform)"
        done
        echo ""
    fi
    
    echo "You're all set! Try:"
    echo "  tfgrid-compose search"
    echo "  tfgrid-compose up single-vm"
    echo ""
}

# Signout command
cmd_signout() {
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
