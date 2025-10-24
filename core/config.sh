#!/usr/bin/env bash
# Configuration management for TFGrid Compose

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CONFIG_DIR="$HOME/.config/tfgrid-compose"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

# Ensure config directory exists
ensure_config_dir() {
    mkdir -p "$CONFIG_DIR"
}

# Get configuration value
config_get() {
    local key="$1"
    local default="${2:-}"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "$default"
        return
    fi

    # Simple YAML parsing for key: value format
    local value=$(grep "^${key}:" "$CONFIG_FILE" 2>/dev/null | sed 's/.*: *//')
    echo "${value:-$default}"
}

# Set configuration value
config_set() {
    local key="$1"
    local value="$2"

    ensure_config_dir

    # Remove existing key if present
    if [ -f "$CONFIG_FILE" ]; then
        sed -i "/^${key}:/d" "$CONFIG_FILE"
    fi

    # Add new key-value pair
    echo "${key}: ${value}" >> "$CONFIG_FILE"
    log_success "Configuration updated: $key = $value"
}

# Show current configuration
show_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_info "No configuration file found at: $CONFIG_FILE"
        log_info "Configuration will use defaults"
        return
    fi

    echo ""
    echo "📋 Current TFGrid Compose Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "File: $CONFIG_FILE"
    echo ""

    while IFS=':' read -r key value; do
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        printf "  %-25s %s\n" "$key:" "$value"
    done < "$CONFIG_FILE"

    echo ""
}

# Initialize default configuration
init_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log_info "Configuration already exists: $CONFIG_FILE"
        return
    fi

    ensure_config_dir

    cat > "$CONFIG_FILE" << 'EOF'
# TFGrid Compose Configuration
# Global settings for node selection and filtering

# Node filtering (comma-separated lists)
# blacklist_nodes: "617,892"
# blacklist_farms: "BadFarm,ProblemFarm"
# whitelist_farms: "Freefarm,TrustedFarm"

# Health thresholds (percentage usage)
# max_cpu_usage: 70
# max_disk_usage: 80

# Minimum uptime requirements (days)
# min_uptime_days: 30
EOF

    log_success "Created default configuration: $CONFIG_FILE"
    log_info "Edit this file to customize node selection behavior"
}

# Export functions
export -f ensure_config_dir
export -f config_get
export -f config_set
export -f show_config
export -f init_config
