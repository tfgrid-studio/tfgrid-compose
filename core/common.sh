#!/usr/bin/env bash
# Common utilities and shared functions for tfgrid-compose

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions (all output to stderr so command substitution works)
log_info() {
    echo -e "${BLUE}ℹ${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}✅${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1" >&2
}

log_error() {
    echo -e "${RED}❌${NC} $1" >&2
}

log_step() {
    echo -e "${CYAN}▶${NC} $1" >&2
}

log_debug() {
    # Debug logging (only show if DEBUG environment variable is set)
    if [ "${DEBUG:-false}" = "true" ]; then
        echo -e "${PURPLE}🐛${NC} $1" >&2
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Check required tools
check_requirements() {
    local missing=()
    
    # Check for Terraform or OpenTofu (prefer OpenTofu)
    if ! command_exists tofu && ! command_exists terraform; then
        missing+=("terraform/tofu")
    fi
    
    if ! command_exists ansible-playbook; then
        missing+=("ansible")
    fi
    
    if ! command_exists yq; then
        log_warning "yq not found, will use basic YAML parsing"
    fi
    
    if ! command_exists jq; then
        missing+=("jq")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing[*]}"
        log_info "Please install: ${missing[*]}"
        echo ""
        echo "Ubuntu/Debian: sudo apt install jq"
        echo "macOS: brew install jq"
        echo "Or visit: https://stedolan.github.io/jq/"
        return 1
    fi
    
    return 0
}

# Parse YAML (basic implementation without yq)
parse_yaml() {
    local file="$1"
    local prefix="$2"
    
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    fi
    
    # If yq is available, use it
    if command_exists yq; then
        # yq is available, use it for better parsing
        return 0
    fi
    
    # Basic parsing without yq (fallback)
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        # Simple key-value parsing
        if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Remove quotes
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            
            # Export as variable
            if [ -n "$prefix" ]; then
                export "${prefix}_${key}=${value}"
            else
                export "${key}=${value}"
            fi
        fi
    done < "$file"
}

# Get value from YAML file
yaml_get() {
    local file="$1"
    local key="$2"
    
    if ! command_exists yq; then
        # Fallback: grep-based extraction
        grep "^${key}:" "$file" | sed 's/^[^:]*:[[:space:]]*//' | sed 's/["\047]//g'
        return
    fi
    
    # Use yq for better extraction
    yq eval ".${key}" "$file" 2>/dev/null || echo ""
}

parse_memory_to_mb() {
    local value="$1"
    if [ -z "$value" ]; then
        echo ""
        return 0
    fi
    local v
    v=$(echo "$value" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    if [[ "$v" =~ ^[0-9]+$ ]]; then
        echo "$v"
        return 0
    fi
    if [[ "$v" =~ ^([0-9]+)g(b)?$ ]]; then
        local n="${BASH_REMATCH[1]}"
        echo $((n * 1024))
        return 0
    fi
    if [[ "$v" =~ ^([0-9]+)m(b)?$ ]]; then
        local n="${BASH_REMATCH[1]}"
        echo "$n"
        return 0
    fi
    log_error "Invalid memory value: $value (expected like 8192, 8G, 8GB)"
    return 1
}

parse_disk_to_gb() {
    local value="$1"
    if [ -z "$value" ]; then
        echo ""
        return 0
    fi
    local v
    v=$(echo "$value" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
    if [[ "$v" =~ ^[0-9]+$ ]]; then
        echo "$v"
        return 0
    fi
    if [[ "$v" =~ ^([0-9]+)g(b)?$ ]]; then
        local n="${BASH_REMATCH[1]}"
        echo "$n"
        return 0
    fi
    if [[ "$v" =~ ^([0-9]+)m(b)?$ ]]; then
        local mb="${BASH_REMATCH[1]}"
        local gb=$(((mb + 1023) / 1024))
        echo "$gb"
        return 0
    fi
    log_error "Invalid disk value: $value (expected like 200, 200G, 200GB)"
    return 1
}

# Validate directory exists
validate_directory() {
    local dir="$1"
    local name="$2"
    
    if [ ! -d "$dir" ]; then
        log_error "$name directory not found: $dir"
        return 1
    fi
    
    return 0
}

# Validate file exists
validate_file() {
    local file="$1"
    local name="$2"
    
    if [ ! -f "$file" ]; then
        log_error "$name file not found: $file"
        return 1
    fi
    
    return 0
}

# Get script directory
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -h "$source" ]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}

# Get deployer root directory
get_deployer_root() {
    # Return the DEPLOYER_ROOT if already set
    if [ -n "$DEPLOYER_ROOT" ]; then
        echo "$DEPLOYER_ROOT"
        return
    fi
    
    # Try to find it from current script
    local source="${BASH_SOURCE[1]}"
    local dir="$(cd -P "$(dirname "$source")" && pwd)"
    
    # Go up until we find patterns/ directory
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/patterns" ]; then
            echo "$dir"
            return
        fi
        dir="$(dirname "$dir")"
    done
    
    # Fallback
    echo "$(pwd)"
}

# Get tfgrid-compose Git commit hash (enhanced with dynamic detection)
get_tfgrid_compose_git_commit() {
    local deployer_root="$(get_deployer_root)"
    
    # Try dynamic Git detection first
    if [ -d "$deployer_root/.git" ]; then
        cd "$deployer_root"
        local commit_hash=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")
        cd - >/dev/null
        if [ "$commit_hash" != "unknown" ]; then
            echo "$commit_hash"
            return 0
        fi
    fi
    
    # Try reading from .version file (saved during make install)
    local version_cache="$deployer_root/.version"
    if [ -f "$version_cache" ]; then
        local cached_commit=$(cat "$version_cache" 2>/dev/null | head -c 7)
        if [[ "$cached_commit" =~ ^[a-f0-9]{7}$ ]]; then
            echo "$cached_commit"
            return 0
        fi
    fi
    
    # Execute VERSION script (for backwards compatibility and dynamic detection)
    local version_file="$deployer_root/VERSION"
    if [ -f "$version_file" ] && [ -x "$version_file" ]; then
        local script_result=$(bash "$version_file" 2>/dev/null || echo "unknown")
        if [[ "$script_result" =~ ^[a-f0-9]{7}$ ]]; then
            echo "$script_result"
            return 0
        fi
    fi
    
    echo "unknown"
}

# Get latest tfgrid-compose version from GitHub
get_latest_tfgrid_compose_version() {
    local latest_commit=""
    
    # Try to get latest commit from GitHub API
    if command_exists curl; then
        latest_commit=$(curl -s "https://api.github.com/repos/tfgrid-studio/tfgrid-compose/commits/main" 2>/dev/null | \
            grep '"sha"' | sed 's/.*"sha": *"\([^"]*\)".*/\1/' | head -c 7)
    elif command_exists wget; then
        latest_commit=$(wget -q -O - "https://api.github.com/repos/tfgrid-studio/tfgrid-compose/commits/main" 2>/dev/null | \
            grep '"sha"' | sed 's/.*"sha": *"\([^"]*\)".*/\1/' | head -c 7)
    fi
    
    # Fallback: try raw file
    if [ -z "$latest_commit" ] && command_exists curl; then
        latest_commit=$(curl -s "https://raw.githubusercontent.com/tfgrid-studio/tfgrid-compose/main/VERSION" 2>/dev/null | head -c 7 || echo "")
    fi
    
    if [ -z "$latest_commit" ]; then
        echo "unknown"
    else
        echo "$latest_commit"
    fi
}
# Get comprehensive tfgrid-compose version info (enhanced with dynamic detection)
get_tfgrid_compose_version() {
    local deployer_root="$(get_deployer_root)"
    local version_file="$deployer_root/VERSION"
    
    # Get Git commit (primary method)
    local git_commit=$(get_tfgrid_compose_git_commit)
    
    # Get semantic version from VERSION file (fallback)
    local semantic_version="unknown"
    if [ -f "$version_file" ]; then
        # Try to execute VERSION script to get result, but also check for semantic version
        local script_result=$(bash "$version_file" 2>/dev/null || echo "unknown")
        
        # If script returns a commit hash, we don't have semantic version
        if [[ "$script_result" =~ ^[a-f0-9]{7}$ ]]; then
            semantic_version="unknown"  # It's a commit hash, not semantic version
        elif [[ "$script_result" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            semantic_version="$script_result"
        fi
    fi
    
    # Determine what to display
    local display_version="$git_commit"
    if [ "$git_commit" = "unknown" ]; then
        display_version="$semantic_version"
    fi
    
    if [ "$git_commit" != "unknown" ]; then
        # Return JSON with both versions
        cat << EOF | jq -c '.'
{
  "semantic": "$semantic_version",
  "git_commit": "$git_commit",
  "display": "$display_version",
  "detection_method": "dynamic_git"
}
EOF
    else
        # No Git info, return semantic version
        cat << EOF | jq -c '.'
{
  "semantic": "$semantic_version",
  "git_commit": "unknown",
  "display": "$display_version",
  "detection_method": "fallback_file"
}
EOF
    fi
}

# Note: STATE_DIR is now set dynamically per app, not globally
# Use STATE_BASE_DIR from deployment-state.sh

# Create state directory
create_state_dir() {
    if [ ! -d "$STATE_DIR" ]; then
        mkdir -p "$STATE_DIR"
        log_info "Created state directory: $STATE_DIR"
    fi
}

# Save to state
state_save() {
    local key="$1"
    local value="$2"
    
    create_state_dir
    echo "${key}: ${value}" >> "$STATE_DIR/state.yaml"
}

# Get from state
state_get() {
    local key="$1"
    
    if [ ! -f "$STATE_DIR/state.yaml" ]; then
        return 1
    fi
    
    grep "^${key}:" "$STATE_DIR/state.yaml" | awk '{print $2}'
}

# Clear state
state_clear() {
    if [ -d "$STATE_DIR" ]; then
        rm -rf "$STATE_DIR"
        log_info "Cleared state directory"
    fi
}

# Check if deployment exists
deployment_exists() {
    [ -f "$STATE_DIR/state.yaml" ]
}

# Show help
show_help() {
    echo -e "${GREEN}TFGrid Compose${NC} - Universal deployment orchestrator for ThreeFold Grid"
    echo ""
    echo -e "${CYAN}Usage:${NC}"
    echo "  tfgrid-compose <command> [options]"
    echo ""
    echo -e "${CYAN}Setup Commands:${NC}"
    echo -e "  ${GREEN}signin${NC} [--check]      Configure credentials (interactive)"
    echo -e "  ${GREEN}signout${NC}                Remove stored credentials"
    echo -e "  ${GREEN}config${NC} <subcommand>   Manage configuration"
    echo -e "  ${GREEN}tfcmd-install${NC}         Install tfcmd for contract management"
    echo ""
    echo -e "${CYAN}Preference Management:${NC}"
    echo -e "  ${GREEN}whitelist${NC} [command]   Manage preferred nodes/farms (enhanced, case-insensitive)"
    echo -e "      (no args)             Interactive menu: add/remove/view/clear"
    echo -e "      nodes <ids>           Set preferred node IDs (e.g., '920,891')"
    echo -e "      farms <names>         Set preferred farms by NAME or ID (case-insensitive)"
    echo -e "      --status              Show current whitelist"
    echo -e "      --clear               Clear all whitelist entries"
    echo -e "      🎯 Enhanced: Supports farm names, IDs, case-insensitive matching"
    echo -e "  ${GREEN}blacklist${NC} [command]   Manage nodes/farms to avoid (enhanced, case-insensitive)"
    echo -e "      (no args)             Interactive menu: add/remove/view/clear"
    echo -e "      nodes <ids>           Set nodes to avoid (e.g., '615,888')"
    echo -e "      farms <names>         Set farms to avoid by NAME or ID (case-insensitive)"
    echo -e "      --status              Show current blacklist"
    echo -e "      --clear               Clear all blacklist entries"
    echo -e "      🚫 Enhanced: Blacklist precedence, case-insensitive matching"
    echo -e "  ${GREEN}preferences${NC} [option]  Manage general preferences"
    echo -e "      --status              Show all preferences"
    echo -e "      --clear               Clear all preferences"
    echo ""
    echo -e "${CYAN}Farm Filtering:${NC}"
    echo -e "  • Farm filtering uses NAMES (not IDs) from node metadata"
    echo -e "  • Find farm names by browsing: ${GREEN}tfgrid-compose nodes${NC}"
    echo -e "  • Example: 'FastFarm', 'Premium Cloud', 'Happy Hosting'"
    echo -e "  • Avoid numeric IDs - use human-readable farm names"
    echo ""
    echo -e "${CYAN}Registry Commands:${NC}"
    echo -e "  ${GREEN}search${NC} [query]        Search available apps in registry"
    echo -e "  ${GREEN}list${NC}                  List deployed apps (local)"
    echo -e "  ${GREEN}select${NC} [app]          Select active app (interactive or direct)"
    echo -e "  ${GREEN}unselect${NC}              Clear app selection"
    echo -e "  ${GREEN}select-project${NC}        Select active project (for selected app)"
    echo -e "  ${GREEN}unselect-project${NC}      Clear project selection"
    echo -e "  ${GREEN}commands${NC}              Show commands for selected app"
    echo ""
    echo -e "${CYAN}Deployment Commands:${NC}"
    echo -e "  ${GREEN}init${NC} <app>            Initialize app configuration (interactive)"
    echo -e "  ${GREEN}up${NC} <app>              Deploy an application (by name or path)"
    echo -e "      ${GREEN}--force${NC}, -f       Force redeploy (destroy + refresh + deploy)"
    echo -e "      ${GREEN}--refresh${NC}         Refresh app cache before deploy"
    echo -e "      ${GREEN}--no-refresh${NC}      Skip cache refresh (use with --force for testing)"
    echo -e "      ${GREEN}--interactive${NC}, -i Interactive node/resource selection"
    echo -e "      ${GREEN}--node${NC} <id>       Deploy to specific node ID"
    echo -e "      ${GREEN}--name${NC} <suffix>   Custom deployment name suffix"
    echo -e "      ${GREEN}--blacklist-node${NC} <ids> Exclude specific nodes (e.g., '617,892')"
    echo -e "      ${GREEN}--blacklist-farm${NC} <names> Exclude specific farm NAMES"
    echo -e "      ${GREEN}--whitelist-nodes${NC} <names> Only use specific nodes"
    echo -e "      ${GREEN}--whitelist-farm${NC} <names> Only use specific farm NAMES"
    echo -e "      ${GREEN}--max-cpu-usage${NC} <0-100> Maximum CPU usage threshold"
    echo -e "      ${GREEN}--max-disk-usage${NC} <0-100> Maximum disk usage threshold"
    echo -e "      ${GREEN}--min-uptime-days${NC} <days> Minimum uptime in days"
    echo -e "  ${GREEN}down${NC} [app]            Destroy a deployment"
    echo -e "  ${GREEN}clean${NC}                 Clean up local state directory"
    echo ""
    echo -e "${CYAN}Status Management:${NC}"
    echo -e "  ${GREEN}status${NC} <subcommand>   Deployment status management"
    echo -e "      ${GREEN}list${NC}              List all deployments with status"
    echo -e "      ${GREEN}health${NC} <name>     Check deployment health"
    echo -e "      ${GREEN}retry${NC} <name>      Retry failed deployment"
    echo -e "      ${GREEN}logs${NC} <name>       Show deployment logs"
    echo -e "      ${GREEN}reset${NC} <name>      Reset deployment status"
    echo -e "      ${GREEN}show${NC} <name>       Show detailed status"
    echo ""
    echo -e "${CYAN}Management Commands:${NC}"
    echo -e "  ${GREEN}exec${NC} <cmd>            Execute command on active app"
    echo -e "  ${GREEN}logs${NC} [app]            Show application logs"
    echo -e "  ${GREEN}status${NC} [app]          Check application status"
    echo -e "  ${GREEN}ssh${NC} [app]             SSH into the deployment"
    echo -e "  ${GREEN}address${NC} [app]         Show deployment addresses"
    echo -e "  ${GREEN}contracts${NC} <subcommand> Contract management via tfcmd (list/show/delete/cancel-all)"
    echo -e "      ${GREEN}list${NC}              List all contracts"
    echo -e "      ${GREEN}delete${NC} <id>       Delete single contract"
    echo -e "      ${GREEN}cancel-all${NC}        Cancel ALL contracts (⚠️ DANGEROUS!)"
    echo -e "  ${GREEN}update-git-config${NC} <app> Update git config on existing VM"
    echo ""
    echo -e "${CYAN}Docker-Style Deployment Commands:${NC}"
    echo -e "  ${GREEN}ps${NC}                    List deployments with timestamps & ages"
    echo -e "  ${GREEN}inspect${NC} <id>          Show deployment details (supports partial IDs)"
    echo -e "  ${GREEN}select${NC} [id/app]       Select deployment (auto-resolves partial IDs)"
    echo ""
    echo -e "${CYAN}Partial ID Resolution Examples:${NC}"
    echo -e "  ${GREEN}t ps${NC}                       # Show all deployments with ages"
    echo -e "  ${GREEN}t login u4${NC}                # Login to deployment starting with 'u4'"
    echo -e "  ${GREEN}t select tfgrid-ai-stack${NC}  # Shows menu if multiple deployments"
    echo ""
    echo -e "${CYAN}Node Browser Commands:${NC}"
    echo -e "  ${GREEN}nodes${NC}                 Interactive node browser (arrow keys to navigate)"
    echo -e "  ${GREEN}nodes show${NC} <id>       Show details for specific node"
    echo ""
    echo -e "${CYAN}Cache Management:${NC}"
    echo -e "  ${GREEN}cache${NC} <subcommand>    Enhanced cache management system"
    echo -e "      ${GREEN}status${NC}             Show cache health overview"
    echo -e "      ${GREEN}list${NC}               List all cached apps with status"
    echo -e "      ${GREEN}outdated${NC}           Show apps needing updates"
    echo -e "      ${GREEN}refresh${NC}            Auto-refresh outdated apps"
    echo -e "      ${GREEN}validate${NC}           Validate cached apps integrity"
    echo -e "      ${GREEN}clear${NC} [app|--all]  Clear cache (specific app or all)"
    echo -e "      ${GREEN}info${NC}               Show cache statistics"
    echo -e "      🆕 ${GREEN}Version-based cache invalidation with smart health checks"
    echo ""
    echo -e "${CYAN}Enhanced Update Commands:${NC}"
    echo -e "  ${GREEN}update${NC} [subcommand]   Smart update system (hybrid strategy)"
    echo -e "      ${GREEN}[none]${NC}             Update tfgrid-compose binary (fast)"
    echo -e "      ${GREEN}<app-name>${NC}         Update specific cached app"
    echo -e "      ${GREEN}registry${NC}           🎉 Update registry + ALL cached apps (comprehensive)"
    echo -e "      ${GREEN}--all-apps${NC}         Update all cached apps only"
    echo -e "      🔄 ${GREEN}Automatic cache refresh with version comparison"
    echo ""
    echo -e "${CYAN}Other Commands:${NC}"
    echo -e "  ${GREEN}patterns${NC}              List available deployment patterns"
    echo -e "  ${GREEN}shortcut${NC} <name>       Create command shortcut (e.g., tfgrid, tf, grid)"
    echo -e "  ${GREEN}docs${NC}                  Open documentation in browser"
    echo -e "  ${GREEN}update${NC}                Update to latest version"
    echo -e "  ${GREEN}dashboard${NC} [start|stop|status|logs] Local web dashboard for apps and deployments"
    echo -e "  ${GREEN}help${NC}                  Show this help message"
    echo ""
    echo -e "${CYAN}Enhanced Cache Examples:${NC}"
    echo "  tfgrid-compose cache status             # Check cache health"
    echo "  tfgrid-compose cache list               # List all cached apps"
    echo "  tfgrid-compose cache outdated           # Show apps needing updates"
    echo "  tfgrid-compose cache refresh            # Auto-update stale apps"
    echo "  tfgrid-compose update tfgrid-ai-stack   # Update specific app"
    echo "  tfgrid-compose update --all-apps        # Update all apps"
    echo "  🎉 tfgrid-compose update registry       # Comprehensive: registry + ALL apps"
    echo ""
    echo -e "${CYAN}Quick Start (New User):${NC}"
    echo "  1. Login:   tfgrid-compose login"
    echo "  2. Search:  tfgrid-compose search"
    echo "  3. Deploy:  tfgrid-compose up single-vm"
    echo "  4. Cache:   tfgrid-compose cache status  # Check cache health"
    echo ""
    echo -e "${CYAN}Docker-Style Usage Examples:${NC}"
    echo "  tfgrid-compose up tfgrid-ai-stack     # Deploy app (auto-generates ID)"
    echo "  tfgrid-compose ps                      # List deployments with timestamps & ages"
    echo "  tfgrid-compose login u4                # Login using partial ID 'u4'"
    echo "  tfgrid-compose select tfgrid-ai-stack  # Auto-select or show menu if multiple"
    echo "  tfgrid-compose inspect abc123def456   # Inspect deployment"
    echo "  tfgrid-compose ssh abc123def456       # SSH to deployment by ID"
    echo ""
    echo -e "${CYAN}Preference Management (Advanced):${NC}"
    echo "  1. Set preferences once:"
    echo "     tfgrid-compose whitelist nodes 920,891"
    echo "     tfgrid-compose whitelist farms 'FastFarm,Premium Cloud'"
    echo "     tfgrid-compose blacklist nodes 615,888"
    echo "     tfgrid-compose blacklist farms 'BadFarm,Problematic'"
    echo "  2. Find farm names: tfgrid-compose nodes"
    echo "  3. Preferences auto-apply to all deployments"
    echo "  4. View preferences:"
    echo "     tfgrid-compose whitelist --status"
    echo "     tfgrid-compose blacklist --status"
    echo "     tfgrid-compose preferences --status"
    echo ""
    echo -e "${CYAN}Contract Management (Existing Users):${NC}"
    echo "  1. Install: tfgrid-compose tfcmd-install"
    echo "  2. List:    tfgrid-compose contracts list"
    echo "  3. Delete:  tfgrid-compose contracts delete <contract-id>"
    echo "  4. Delete all: tfgrid-compose contracts delete --all"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo "  tfgrid-compose login                     # Setup credentials"
    echo ""
    echo -e "${CYAN}Enhanced Whitelist/Blacklist (v0.13.4+):${NC}"
    echo "  tfgrid-compose whitelist                 # Interactive menu (7 options)"
    echo "  tfgrid-compose blacklist                 # Interactive menu (case-insensitive)"
    echo "  tfgrid-compose whitelist nodes 920,891   # Set preferred nodes"
    echo "  tfgrid-compose whitelist farms 'Freefarm,1,MIXNMATCH'  # Names + IDs, case-insensitive"
    echo "  tfgrid-compose blacklist farms 'BadFarm,2'  # Avoid farms by name or ID"
    echo "  tfgrid-compose whitelist --status        # View current whitelist"
    echo "  tfgrid-compose blacklist --clear         # Clear all blacklist entries"
    echo ""
    echo -e "${CYAN}Node Management:${NC}"
    echo "  tfgrid-compose nodes                     # Browse nodes to find farm names"
    echo "  tfgrid-compose nodes show 123            # Check specific node details"
    echo ""
    echo -e "${CYAN}App Deployment:${NC}"
    echo "  tfgrid-compose search                    # Browse all apps"
    echo "  tfgrid-compose search ai                 # Search for AI apps"
    echo "  tfgrid-compose up single-vm              # Deploy single VM"
    echo "  tfgrid-compose up tfgrid-ai-stack        # Deploy from registry (auto-refresh cache)"
    echo "  tfgrid-compose up tfgrid-ai-stack --refresh  # Force fresh cache"
    echo "  tfgrid-compose up tfgrid-ai-stack --force    # Complete fresh start"
    echo "  tfgrid-compose up ./my-app               # Deploy from local path"
    echo "  tfgrid-compose list                      # List deployed apps"
    echo "  tfgrid-compose select                    # Select active app (interactive)"
    echo "  tfgrid-compose commands                  # Show app commands"
    echo "  tfgrid-compose logs                      # Logs for active app"
    echo "  tfgrid-compose exec create my-project    # Run command on active app"
    echo "  tfgrid-compose shortcut tf               # Create 'tf' shortcut"
    echo ""
    echo -e "${CYAN}Contract Management:${NC}"
    echo "  tfgrid-compose tfcmd-install             # Install tfcmd tool"
    echo "  tfgrid-compose contracts list            # List your contracts"
    echo "  tfgrid-compose contracts delete <id>     # Cancel a contract (wraps tfcmd cancel)"
    echo "  tfgrid-compose contracts delete --all    # Delete all contracts (wraps tfcmd cancel-all)"
    echo ""
    echo -e "${CYAN}Documentation:${NC}"
    echo "  https://docs.tfgrid.studio"
    echo ""
    # Read version from VERSION file if not already set
    local version="${VERSION}"
    if [ -z "$version" ]; then
        version=$(cat "$(dirname "${BASH_SOURCE[0]}")/../VERSION" 2>/dev/null || echo "unknown")
    fi
    echo -e "${CYAN}Version:${NC} $version"
}

# Export functions for use in other scripts
export -f log_info
export -f log_success
export -f log_warning
export -f log_error
export -f log_step
export -f command_exists
export -f validate_directory
export -f validate_file
export -f yaml_get
export -f parse_memory_to_mb
export -f parse_disk_to_gb
export -f state_save
export -f state_get
export -f state_clear
export -f deployment_exists

# Export Git version functions
export -f get_tfgrid_compose_git_commit
export -f get_tfgrid_compose_version
