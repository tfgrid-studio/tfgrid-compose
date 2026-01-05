#!/usr/bin/env bash
# TFGrid Compose - Git Configuration Module
# Handles git identity management with context support

# Git config file locations
GIT_CONFIG_DIR="$HOME/.config/tfgrid-compose"
GIT_CONFIG_FILE="$GIT_CONFIG_DIR/git-configs.yaml"

# Ensure config directory exists
ensure_gitconfig_dir() {
    mkdir -p "$GIT_CONFIG_DIR"
}

# Check if git is available
check_git() {
    if ! command -v git &> /dev/null; then
        log_error "Git is not installed"
        return 1
    fi
    return 0
}

# Show current git config
show_current_config() {
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

# Git config command
cmd_gitconfig() {
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
                echo "  tfgrid-compose gitconfig                    # Set default git config"
                echo "  tfgrid-compose gitconfig --context=github   # Set GitHub-specific config"
                echo "  tfgrid-compose gitconfig --context=gitea    # Set Gitea-specific config"
                echo "  tfgrid-compose gitconfig --context=forgejo  # Set Forgejo-specific config"
                echo "  tfgrid-compose gitconfig --context=tfgrid-ai-agent  # Set AI agent config"
                echo "  tfgrid-compose gitconfig --show             # Show current config"
                echo ""
                echo "CONTEXTS:"
                echo "  github          - For ~/code/github.com/ repos"
                echo "  gitea           - For ~/code/git.ourworld.tf/ repos"
                echo "  forgejo         - For ~/code/forge.ourworld.tf/ repos"
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
                echo "Run 'tfgrid-compose gitconfig --help' for usage"
                echo ""
                return 1
                ;;
        esac
    done

    # Check git availability
    if ! check_git; then
        return 1
    fi

    # Show current config if requested
    if [ "$show_only" = true ]; then
        show_current_config
        return 0
    fi

    # Determine context description
    local context_desc=""
    case "$context" in
        github)
            context_desc="GitHub repositories"
            ;;
        gitea)
            context_desc="Gitea repositories (git.ourworld.tf)"
            ;;
        forgejo)
            context_desc="Forgejo repositories (forge.ourworld.tf)"
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
    echo "  tfgrid-compose gitconfig --context=github"
    echo "  tfgrid-compose gitconfig --context=gitea"
    echo "  tfgrid-compose gitconfig --context=forgejo"
    echo "  tfgrid-compose gitconfig --context=tfgrid-ai-agent"
    echo ""
}