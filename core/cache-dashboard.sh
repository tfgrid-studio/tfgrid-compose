#!/usr/bin/env bash
# TFGrid Compose - Cache Health Monitoring Dashboard
# Comprehensive cache monitoring with visual indicators and statistics

# Source required modules
source "$(dirname "${BASH_SOURCE[0]}")/app-cache.sh"

# Dashboard configuration
DASHBOARD_UPDATE_INTERVAL=30  # seconds
CACHE_HISTORY_FILE="$HOME/.config/tfgrid-compose/cache-history.log"

# Color codes for visual indicators
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Unicode characters for visual elements
CHECK_MARK="✅"
CROSS_MARK="❌"
WARNING="⚠️"
REFRESH="🔄"
INFO="ℹ️"
ROCKET="🚀"
CHART="📊"
CLOCK="🕒"
DISK="💾"
GIT="📁"

# Initialize dashboard
init_dashboard() {
    # Create history file if it doesn't exist
    mkdir -p "$(dirname "$CACHE_HISTORY_FILE")"
    touch "$CACHE_HISTORY_FILE"
    
    # Clear screen and show header
    clear
    show_dashboard_header
}

# Show dashboard header
show_dashboard_header() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${ROCKET}${BLUE} TFGrid Compose Cache Health Dashboard${NC}  ${ROCKET}${NC}"
    echo -e "${BLUE}║${NC}  ${INFO} Real-time cache monitoring and performance analytics ${NC}"
    echo -e "${BLUE}║${NC}  ${CLOCK} Last updated: $(date '+%Y-%m-%d %H:%M:%S') ${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Get cache statistics
get_cache_stats() {
    local cache_dir="$APPS_CACHE_DIR"
    local metadata_dir="$CACHE_METADATA_DIR"
    
    # Basic counts
    local total_apps=0
    local healthy_apps=0
    local stale_apps=0
    local invalid_apps=0
    local not_cached=0
    
    # Size calculations
    local cache_size=0
    local metadata_size=0
    
    # Calculate cache size
    if [ -d "$cache_dir" ]; then
        cache_size=$(du -sh "$cache_dir" 2>/dev/null | cut -f1)
    fi
    
    # Calculate metadata size
    if [ -d "$metadata_dir" ]; then
        metadata_size=$(du -sh "$metadata_dir" 2>/dev/null | cut -f1)
    fi
    
    # Count apps and their status
    if [ -d "$cache_dir" ]; then
        for app_dir in "$cache_dir"/*; do
            if [ -d "$app_dir" ] && [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]; then
                ((total_apps++))
                local app_name=$(basename "$app_dir")
                
                if ! validate_cached_app "$app_name" >/dev/null 2>&1; then
                    ((invalid_apps++))
                elif cache_needs_update "$app_name"; then
                    ((stale_apps++))
                else
                    ((healthy_apps++))
                fi
            fi
        done
    fi
    
    # Calculate totals
    local registry_apps=$(t search 2>/dev/null | grep -c "tfgrid-" || echo "0")
    
    echo "$total_apps|$healthy_apps|$stale_apps|$invalid_apps|$cache_size|$metadata_size|$registry_apps"
}

# Show cache overview
show_cache_overview() {
    local stats=$(get_cache_stats)
    IFS='|' read -r total_apps healthy_apps stale_apps invalid_apps cache_size metadata_size registry_apps <<< "$stats"
    
    echo -e "${CYAN}📊 Cache Overview${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # Health status with visual indicators
    echo -e "${GREEN}${CHECK_MARK} Healthy Apps:${NC} $healthy_apps"
    echo -e "${YELLOW}${REFRESH} Stale Apps:${NC} $stale_apps"
    echo -e "${RED}${CROSS_MARK} Invalid Apps:${NC} $invalid_apps"
    echo -e "${BLUE}${INFO} Total Cached:${NC} $total_apps"
    echo -e "${MAGENTA}${CHART} Available in Registry:${NC} $registry_apps"
    
    echo ""
    
    # Storage usage
    echo -e "${DISK} Storage Usage:"
    echo -e "  ${BLUE}Cache:${NC} $cache_size"
    echo -e "  ${BLUE}Metadata:${NC} $metadata_size"
    
    echo ""
}

# Show detailed app health
show_app_health_details() {
    echo -e "${CYAN}🏥 Detailed App Health${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    
    local cache_dir="$APPS_CACHE_DIR"
    
    if [ ! -d "$cache_dir" ] || [ -z "$(ls -A "$cache_dir" 2>/dev/null)" ]; then
        echo -e "${YELLOW}${INFO} No cached apps found${NC}"
        echo ""
        return
    fi
    
    # Table header
    printf "%-20s %-10s %-12s %-15s %-15s %-10s\n" "APP NAME" "STATUS" "COMMIT" "LAST UPDATED" "HEALTH SCORE" "COMMANDS"
    echo "────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
    
    for app_dir in "$cache_dir"/*; do
        if [ -d "$app_dir" ] && [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]; then
            local app_name=$(basename "$app_dir")
            local health_info=$(get_cache_health "$app_name")
            local status=$(echo "$health_info" | jq -r '.status')
            local commit=$(echo "$health_info" | jq -r '.metadata.commit_hash // "unknown"' | cut -c1-8)
            local last_updated=$(echo "$health_info" | jq -r '.last_updated')
            
            # Convert timestamp to readable format
            if [ "$last_updated" != "0" ] && [ "$last_updated" != "null" ]; then
                last_updated=$(date -d "@$last_updated" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "unknown")
            else
                last_updated="unknown"
            fi
            
            # Calculate health score
            local health_score="100%"
            case "$status" in
                "healthy") health_score="100%" ;;
                "stale") health_score="75%" ;;
                "invalid") health_score="25%" ;;
                *) health_score="0%" ;;
            esac
            
            # Status emoji
            local status_emoji=""
            case "$status" in
                "healthy") status_emoji="${GREEN}${CHECK_MARK}${NC}" ;;
                "stale") status_emoji="${YELLOW}${REFRESH}${NC}" ;;
                "invalid") status_emoji="${RED}${CROSS_MARK}${NC}" ;;
                *) status_emoji="${BLUE}${INFO}${NC}" ;;
            esac
            
            # Count commands (simplified)
            local command_count="0"
            if [ -f "$app_dir/tfgrid-compose.yaml" ]; then
                command_count=$(grep -c "^[a-z_]*:" "$app_dir/tfgrid-compose.yaml" 2>/dev/null || echo "0")
            fi
            
            printf "%-20s %-10s %-12s %-15s %-15s %-10s\n" \
                "$app_name" "$status_emoji" "$commit" "$last_updated" "$health_score" "$command_count"
        fi
    done
    
    echo ""
}

# Show Git-based cache analytics
show_git_analytics() {
    echo -e "${CYAN}${GIT} Git-Based Cache Analytics${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    
    local cache_dir="$APPS_CACHE_DIR"
    local git_tracked=0
    local total_commits=0
    local avg_commits=0
    local oldest_cache=""
    local newest_cache=""
    
    if [ -d "$cache_dir" ]; then
        for app_dir in "$cache_dir"/*; do
            if [ -d "$app_dir" ] && [ -d "$app_dir/.git" ]; then
                ((git_tracked++))
                cd "$app_dir"
                
                # Count commits in this repository
                local commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
                ((total_commits += commit_count))
                
                # Get oldest commit date
                local oldest_commit_date=$(git log --format=%ct --reverse 2>/dev/null | head -1)
                if [ -n "$oldest_commit_date" ] && [ "$oldest_commit_date" -gt 0 ]; then
                    if [ -z "$oldest_cache" ] || [ "$oldest_commit_date" -lt "$oldest_cache" ]; then
                        oldest_cache="$oldest_commit_date"
                    fi
                fi
                
                # Get newest commit date
                local newest_commit_date=$(git log --format=%ct -1 2>/dev/null)
                if [ -n "$newest_commit_date" ]; then
                    if [ -z "$newest_cache" ] || [ "$newest_commit_date" -gt "$newest_cache" ]; then
                        newest_cache="$newest_commit_date"
                    fi
                fi
                
                cd - >/dev/null
            fi
        done
    fi
    
    # Calculate averages
    if [ $git_tracked -gt 0 ]; then
        avg_commits=$((total_commits / git_tracked))
    fi
    
    # Display analytics
    echo -e "${GREEN}${GIT} Git-Tracked Apps:${NC} $git_tracked"
    echo -e "${BLUE}${CHART} Total Commits Across All Apps:${NC} $total_commits"
    echo -e "${YELLOW}${CLOCK} Average Commits per App:${NC} $avg_commits"
    
    if [ -n "$oldest_cache" ] && [ "$oldest_cache" -gt 0 ]; then
        echo -e "${MAGENTA}${CLOCK} Oldest Cache:${NC} $(date -d "@$oldest_cache" '+%Y-%m-%d %H:%M')"
    fi
    
    if [ -n "$newest_cache" ] && [ "$newest_cache" -gt 0 ]; then
        echo -e "${CYAN}${CLOCK} Newest Cache:${NC} $(date -d "@$newest_cache" '+%Y-%m-%d %H:%M')"
    fi
    
    echo ""
}

# Show performance metrics
show_performance_metrics() {
    echo -e "${CYAN}⚡ Performance Metrics${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    
    # Calculate cache efficiency
    local total_apps=0
    local healthy_apps=0
    local cache_hit_rate=0
    
    if [ -d "$APPS_CACHE_DIR" ]; then
        for app_dir in "$APPS_CACHE_DIR"/*; do
            if [ -d "$app_dir" ] && [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]; then
                ((total_apps++))
                local app_name=$(basename "$app_dir")
                if ! cache_needs_update "$app_name" >/dev/null 2>&1; then
                    ((healthy_apps++))
                fi
            fi
        done
    fi
    
    if [ $total_apps -gt 0 ]; then
        cache_hit_rate=$((healthy_apps * 100 / total_apps))
    fi
    
    # Display metrics
    echo -e "${GREEN}Cache Hit Rate:${NC} ${cache_hit_rate}%"
    echo -e "${BLUE}Cache Efficiency:${NC} $healthy_apps/$total_apps apps healthy"
    
    # Estimate time savings
    local estimated_seconds_saved=0
    if [ $total_apps -gt 0 ]; then
        # Estimate: each app cache saves ~10 seconds of download
        estimated_seconds_saved=$((total_apps * 10))
    fi
    
    local time_saved_min=$((estimated_seconds_saved / 60))
    local time_saved_sec=$((estimated_seconds_saved % 60))
    
    echo -e "${YELLOW}Estimated Time Saved:${NC} ${time_saved_min}m ${time_saved_sec}s"
    
    # Last cleanup info
    if [ -f "$CACHE_HISTORY_FILE" ]; then
        local last_cleanup=$(tail -1 "$CACHE_HISTORY_FILE" 2>/dev/null | grep "cleanup" | tail -1 || echo "")
        if [ -n "$last_cleanup" ]; then
            echo -e "${MAGENTA}${CLOCK} Last Cleanup:${NC} $last_cleanup"
        fi
    fi
    
    echo ""
}

# Show alerts and recommendations
show_alerts_and_recommendations() {
    echo -e "${CYAN}🚨 Alerts & Recommendations${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    
    local alert_count=0
    local recommendation_count=0
    
    # Check for stale apps
    if [ -d "$APPS_CACHE_DIR" ]; then
        for app_dir in "$APPS_CACHE_DIR"/*; do
            if [ -d "$app_dir" ] && [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]; then
                local app_name=$(basename "$app_dir")
                if cache_needs_update "$app_name" >/dev/null 2>&1; then
                    echo -e "${YELLOW}${WARNING} Stale Cache Detected:${NC} $app_name needs update"
                    ((alert_count++))
                fi
            fi
        done
    fi
    
    # Check for invalid apps
    if [ -d "$APPS_CACHE_DIR" ]; then
        for app_dir in "$APPS_CACHE_DIR"/*; do
            if [ -d "$app_dir" ] && [ -d "$app_dir/.git" ] && [ -f "$app_dir/tfgrid-compose.yaml" ]; then
                local app_name=$(basename "$app_dir")
                if ! validate_cached_app "$app_name" >/dev/null 2>&1; then
                    echo -e "${RED}${CROSS_MARK} Invalid Cache:${NC} $app_name has validation issues"
                    ((alert_count++))
                fi
            fi
        done
    fi
    
    # Recommendations
    if [ -d "$APPS_CACHE_DIR" ] && [ -n "$(ls -A "$APPS_CACHE_DIR" 2>/dev/null)" ]; then
        echo -e "${BLUE}${INFO} Recommendations:"
        echo -e "  ${GREEN}✓${NC} Run 't cache refresh' to update stale apps"
        echo -e "  ${GREEN}✓${NC} Run 't cache validate' to check all caches"
        echo -e "  ${GREEN}✓${NC} Consider 't cache clear' for unused apps"
        echo -e "  ${GREEN}✓${NC} Monitor with 't cache monitor' for ongoing health"
        ((recommendation_count += 4))
    else
        echo -e "${BLUE}${INFO} No cached apps - deploy an app to get started:"
        echo -e "  ${GREEN}✓${NC} Run 't search' to see available apps"
        echo -e "  ${GREEN}✓${NC} Run 't up <app-name>' to deploy"
        ((recommendation_count += 2))
    fi
    
    # Summary
    echo ""
    if [ $alert_count -eq 0 ] && [ $recommendation_count -gt 0 ]; then
        echo -e "${GREEN}${CHECK_MARK} Cache Status:${NC} Healthy - $(($recommendation_count)) recommendations available"
    elif [ $alert_count -gt 0 ]; then
        echo -e "${YELLOW}${WARNING} Cache Status:${NC} Needs attention - $alert_count alerts, $recommendation_count recommendations"
    else
        echo -e "${BLUE}${INFO} Cache Status:${NC} No cached apps - start by deploying an application"
    fi
    
    echo ""
}

# Log cache event to history
log_cache_event() {
    local event_type="$1"
    local details="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $event_type: $details" >> "$CACHE_HISTORY_FILE"
}

# Show historical data
show_historical_data() {
    echo -e "${CYAN}📈 Historical Data${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    
    if [ ! -f "$CACHE_HISTORY_FILE" ] || [ ! -s "$CACHE_HISTORY_FILE" ]; then
        echo -e "${BLUE}${INFO} No historical data available${NC}"
        echo -e "${BLUE}${INFO} Historical logging will appear here after cache operations${NC}"
        echo ""
        return
    fi
    
    echo -e "${BLUE}Recent Cache Events:${NC}"
    echo ""
    
    # Show last 10 events
    tail -10 "$CACHE_HISTORY_FILE" | while read -r line; do
        echo -e "  ${GREEN}•${NC} $line"
    done
    
    echo ""
    
    # Show event statistics
    local total_events=$(wc -l < "$CACHE_HISTORY_FILE")
    local cleanup_events=$(grep -c "cleanup" "$CACHE_HISTORY_FILE" || echo "0")
    local update_events=$(grep -c "update" "$CACHE_HISTORY_FILE" || echo "0")
    local validate_events=$(grep -c "validate" "$CACHE_HISTORY_FILE" || echo "0")
    
    echo -e "${BLUE}Event Summary:${NC}"
    echo -e "  ${YELLOW}Total Events:${NC} $total_events"
    echo -e "  ${GREEN}Cleanup Events:${NC} $cleanup_events"
    echo -e "  ${BLUE}Update Events:${NC} $update_events"
    echo -e "  ${CYAN}Validation Events:${NC} $validate_events"
    
    echo ""
}

# Show controls/help
show_controls() {
    echo -e "${CYAN}🎮 Dashboard Controls${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Available Actions:${NC}"
    echo -e "  ${BLUE}r${NC} - Refresh dashboard"
    echo -e "  ${BLUE}c${NC} - Clear cache"
    echo -e "  ${BLUE}u${NC} - Update all apps"
    echo -e "  ${BLUE}v${NC} - Validate all caches"
    echo -e "  ${BLUE}h${NC} - Show help"
    echo -e "  ${BLUE}q${NC} - Quit dashboard"
    echo -e "  ${BLUE}m${NC} - Run maintenance tasks"
    echo ""
    echo -e "${BLUE}External Commands:${NC}"
    echo -e "  ${YELLOW}t cache refresh${NC} - Update all stale apps"
    echo -e "  ${YELLOW}t cache clear${NC} - Clear all cache"
    echo -e "  ${YELLOW}t cache validate${NC} - Validate all caches"
    echo -e "  ${YELLOW}t up <app>${NC} - Deploy new app"
    echo ""
}

# Handle user input
handle_input() {
    local input
    echo -e "${BLUE}Press 'h' for help or 'q' to quit. Auto-refresh in ${DASHBOARD_UPDATE_INTERVAL}s...${NC}"
    echo ""
    
    # Set timeout for read command
    if read -t $DASHBOARD_UPDATE_INTERVAL -r input 2>/dev/null; then
        case "$input" in
            [rR])
                echo -e "${GREEN}${REFRESH} Refreshing dashboard...${NC}"
                return 0
                ;;
            [cC])
                echo -e "${YELLOW}${WARNING} Clear cache requested${NC}"
                echo -e "${BLUE}Use 't cache clear --force' to proceed${NC}"
                return 0
                ;;
            [uU])
                echo -e "${BLUE}${CLOCK} Update all apps requested${NC}"
                echo -e "${BLUE}Use 't cache refresh' to proceed${NC}"
                return 0
                ;;
            [vV])
                echo -e "${CYAN}${CHECK_MARK} Validate caches requested${NC}"
                echo -e "${BLUE}Use 't cache validate' to proceed${NC}"
                return 0
                ;;
            [mM])
                echo -e "${YELLOW}${WARNING} Maintenance requested${NC}"
                echo -e "${BLUE}Consider running 't cache refresh' and 't cache validate'${NC}"
                return 0
                ;;
            [hH]|"help")
                show_controls
                echo -e "${BLUE}Press any key to continue...${NC}"
                read -r
                return 0
                ;;
            [qQ]|"quit"|"exit")
                echo -e "${GREEN}${CHECK_MARK} Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${BLUE}${INFO} Unknown command: $input${NC}"
                echo -e "${BLUE}Press 'h' for help${NC}"
                return 0
                ;;
        esac
    else
        # Timeout reached, auto-refresh
        return 0
    fi
}

# Main dashboard loop
run_dashboard() {
    local refresh_count=0
    
    while true; do
        # Show dashboard components
        show_cache_overview
        show_app_health_details
        show_git_analytics
        show_performance_metrics
        show_alerts_and_recommendations
        show_historical_data
        show_controls
        
        # Handle user input
        handle_input
        refresh_count=$((refresh_count + 1))
        
        # Log periodic refresh
        if [ $((refresh_count % 4)) -eq 0 ]; then
            log_cache_event "dashboard_refresh" "Dashboard auto-refresh #$refresh_count"
        fi
        
        # Update header with refresh count
        clear
        show_dashboard_header
    done
}

# Single-shot dashboard (no auto-refresh)
show_single_dashboard() {
    init_dashboard
    show_cache_overview
    show_app_health_details
    show_git_analytics
    show_performance_metrics
    show_alerts_and_recommendations
    show_historical_data
    show_controls
    
    log_cache_event "dashboard_view" "Single dashboard view"
}

# Export functions for use in CLI
export -f show_single_dashboard
export -f run_dashboard

# If called directly, show dashboard
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    if [ "${1:-}" = "--monitor" ] || [ "${1:-}" = "-m" ]; then
        echo -e "${GREEN}Starting cache monitoring dashboard...${NC}"
        echo -e "${BLUE}Press Ctrl+C to stop, 'h' for help, 'q' to quit${NC}"
        echo ""
        run_dashboard
    else
        show_single_dashboard
    fi

# Wrapper functions for CLI integration
cache_dashboard_monitor() {
    # Start the monitoring dashboard with auto-refresh
    echo -e "${GREEN}🚀 Starting cache monitoring dashboard...${NC}"
    echo -e "${BLUE}Press Ctrl+C to stop, 'h' for help, 'q' to quit${NC}"
    echo ""
    run_dashboard
}

cache_dashboard_show() {
    # Show a single dashboard view (no auto-refresh)
    show_single_dashboard
}

# Export wrapper functions
export -f cache_dashboard_monitor
export -f cache_dashboard_show
fi