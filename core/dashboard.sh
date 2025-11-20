#!/usr/bin/env bash

# Dashboard management module for tfgrid-compose CLI
# Encapsulates all logic related to starting/stopping the TFGrid Studio dashboard,
# installing the desktop launcher, and viewing logs/status.

set -e

# Start or manage the local web dashboard
cmd_dashboard() {
  local action="${1:-}"

  local DASHBOARD_HOME="$HOME/.config/tfgrid-compose/dashboard"
  local DASHBOARD_SERVER="$DASHBOARD_HOME/server.js"
  local DASHBOARD_PID_FILE="$DASHBOARD_HOME/dashboard.pid"
  local DASHBOARD_PORT_FILE="$DASHBOARD_HOME/dashboard-port"

  # If no explicit action is provided and a background dashboard is already running,
  # report its status instead of starting another instance.
  if [ -z "$action" ] && [ -f "$DASHBOARD_PID_FILE" ]; then
    local DASHBOARD_PID
    DASHBOARD_PID=$(cat "$DASHBOARD_PID_FILE" 2>/dev/null || true)
    if [ -n "$DASHBOARD_PID" ] && ps -p "$DASHBOARD_PID" >/dev/null 2>&1; then
      local DASHBOARD_PORT=""
      if [ -f "$DASHBOARD_PORT_FILE" ]; then
        DASHBOARD_PORT=$(cat "$DASHBOARD_PORT_FILE" 2>/dev/null || true)
      fi
      if [ -n "$DASHBOARD_PORT" ]; then
        log_info "Dashboard already running at http://localhost:$DASHBOARD_PORT (pid $DASHBOARD_PID)"
      else
        log_info "Dashboard already running (pid $DASHBOARD_PID)"
      fi
      return 0
    else
      rm -f "$DASHBOARD_PID_FILE"
    fi
  fi

  case "$action" in
    stop)
      _dashboard_stop "$DASHBOARD_HOME" "$DASHBOARD_PID_FILE" || true
      ;;
    status)
      _dashboard_status "$DASHBOARD_HOME" "$DASHBOARD_PID_FILE" "$DASHBOARD_PORT_FILE"
      ;;
    logs)
      _dashboard_logs "$DASHBOARD_HOME"
      ;;
    desktop)
      _dashboard_install_desktop_launcher
      ;;
    start)
      _dashboard_bootstrap "$DASHBOARD_HOME" || return 1
      _dashboard_ensure_runtime "$DASHBOARD_HOME" || return 1
      _dashboard_start_background "$DASHBOARD_HOME" "$DASHBOARD_SERVER" "$DASHBOARD_PID_FILE" "$DASHBOARD_PORT_FILE"
      ;;
    ""|run)
      _dashboard_bootstrap "$DASHBOARD_HOME" || return 1
      _dashboard_ensure_runtime "$DASHBOARD_HOME" || return 1
      _dashboard_run_foreground "$DASHBOARD_HOME" "$DASHBOARD_SERVER"
      ;;
    *)
      log_error "Unknown dashboard action: $action"
      echo "Available actions: start, stop, status, logs, desktop"
      return 1
      ;;
  esac
}

_dashboard_stop() {
  local home="$1"
  local pid_file="$2"

  if [ -f "$pid_file" ]; then
    local pid
    pid=$(cat "$pid_file" 2>/dev/null || true)
    if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
      kill "$pid" 2>/dev/null || true
      for _ in $(seq 1 50); do
        if ! ps -p "$pid" >/dev/null 2>&1; then
          break
        fi
        sleep 0.1
      done
      log_success "Stopped dashboard (pid $pid)"
    else
      log_info "Dashboard is not running"
    fi
    rm -f "$pid_file"
  else
    log_info "Dashboard is not running"
  fi
}

_dashboard_status() {
  local home="$1"
  local pid_file="$2"
  local port_file="$3"

  if [ -f "$pid_file" ]; then
    local pid
    pid=$(cat "$pid_file" 2>/dev/null || true)
    if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
      local port=""
      if [ -f "$port_file" ]; then
        port=$(cat "$port_file" 2>/dev/null || true)
      fi
      if [ -n "$port" ]; then
        log_info "Dashboard running at http://localhost:$port (pid $pid)"
      else
        log_info "Dashboard running (pid $pid)"
      fi
    else
      log_info "Dashboard is not running"
      rm -f "$pid_file"
    fi
  else
    log_info "Dashboard is not running"
  fi
}

_dashboard_logs() {
  local home="$1"
  local log_file="$home/dashboard.log"

  if [ ! -f "$log_file" ]; then
    log_info "No dashboard log file found at $log_file"
    return 0
  fi

  tail -n 200 -f "$log_file"
}

_dashboard_install_desktop_launcher() {
  local LAUNCHER_DIR="$HOME/.local/bin"
  local LAUNCHER_PATH="$LAUNCHER_DIR/tfgrid-dashboard-launcher"
  local APPLICATIONS_DIR="$HOME/.local/share/applications"
  local DESKTOP_FILE="$APPLICATIONS_DIR/tfgrid-dashboard.desktop"
  local DESKTOP_DIR="$HOME/Desktop"

  mkdir -p "$LAUNCHER_DIR" "$APPLICATIONS_DIR"

  cat >"$LAUNCHER_PATH" <<'EOF'
#!/usr/bin/env bash
set -e

# Show notification helper
notify() {
  local title="$1"
  local message="$2"
  local urgency="${3:-normal}"
  
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
  fi
}

launch_app_window() {
  local url="$1"

  # Prefer Brave/Chromium in a dedicated incognito window with the dashboard URL
  if command -v brave-browser >/dev/null 2>&1; then
    brave-browser --incognito --new-window --kiosk "$url" >/dev/null 2>&1 &
    return
  fi

  if command -v brave-browser-stable >/dev/null 2>&1; then
    brave-browser-stable --incognito --new-window --kiosk "$url" >/dev/null 2>&1 &
    return
  fi

  if command -v brave >/dev/null 2>&1; then
    brave --incognito --new-window --kiosk "$url" >/dev/null 2>&1 &
    return
  fi

  if command -v google-chrome >/dev/null 2>&1; then
    google-chrome --incognito --new-window --kiosk "$url" >/dev/null 2>&1 &
    return
  fi

  if command -v google-chrome-stable >/dev/null 2>&1; then
    google-chrome-stable --incognito --new-window --kiosk "$url" >/dev/null 2>&1 &
    return
  fi

  if command -v chromium >/dev/null 2>&1; then
    chromium --incognito --new-window --kiosk "$url" >/dev/null 2>&1 &
    return
  fi

  if command -v chromium-browser >/dev/null 2>&1; then
    chromium-browser --incognito --new-window --kiosk "$url" >/dev/null 2>&1 &
    return
  fi

  if command -v firefox >/dev/null 2>&1; then
    firefox --private-window --kiosk "$url" >/dev/null 2>&1 &
    return
  fi

  if command -v firefox-esr >/dev/null 2>&1; then
    firefox-esr --private-window --kiosk "$url" >/dev/null 2>&1 &
    return
  fi

  # Fallback to system default browser
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
  else
    echo "Open $url in your browser"
  fi
}

# Check if dashboard is already running and responding
is_dashboard_ready() {
  if command -v curl >/dev/null 2>&1; then
    curl -s -f -o /dev/null --max-time 1 "$URL" 2>/dev/null
    return $?
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O /dev/null --timeout=1 "$URL" 2>/dev/null
    return $?
  else
    # No curl/wget, assume it's ready after starting
    return 0
  fi
}

DASHBOARD_HOME="$HOME/.config/tfgrid-compose/dashboard"
DASHBOARD_PORT_FILE="$DASHBOARD_HOME/dashboard-port"
PORT="${TFGRID_DASHBOARD_PORT:-43100}"

if [ -f "$DASHBOARD_PORT_FILE" ]; then
  P=$(cat "$DASHBOARD_PORT_FILE" 2>/dev/null || true)
  if [ -n "$P" ]; then
    PORT="$P"
  fi
fi

URL="http://localhost:$PORT"

# If dashboard is already ready, just open browser
if is_dashboard_ready; then
  launch_app_window "$URL"
  exit 0
fi

# Dashboard not ready, start it and wait
notify "TFGrid Studio" "Starting dashboard server..."

# Start dashboard in background
tfgrid-compose dashboard start >/dev/null 2>&1 || true

# Wait for dashboard to be ready (max 15 seconds)
MAX_WAIT=15
WAITED=0

while [ $WAITED -lt $MAX_WAIT ]; do
  if is_dashboard_ready; then
    notify "TFGrid Studio" "Dashboard ready! Opening browser..."
    sleep 0.5  # Brief pause so user sees the notification
    launch_app_window "$URL"
    exit 0
  fi
  sleep 0.5
  WAITED=$((WAITED + 1))
done

# Timeout - dashboard didn't start in time
notify "TFGrid Studio" "Dashboard failed to start. Check logs with: t dashboard logs" "critical"
exit 1
EOF

  chmod +x "$LAUNCHER_PATH"

  local ICON_NAME="tfgrid-studio-dashboard"
  local ICON_TARGET_DIR="$HOME/.local/share/icons"
  local ICON_PATH="$ICON_TARGET_DIR/$ICON_NAME.svg"
  local TEMPLATE_DIR="$DEPLOYER_ROOT/dashboard"
  local FAVICON_SOURCE="$TEMPLATE_DIR/public/favicon.svg"

  if [ -f "$FAVICON_SOURCE" ]; then
    mkdir -p "$ICON_TARGET_DIR"
    cp "$FAVICON_SOURCE" "$ICON_PATH" 2>/dev/null || true
  fi

  cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=TFGrid Studio Dashboard
Comment=Local dashboard for tfgrid-compose apps and deployments
Exec=$LAUNCHER_PATH
Terminal=false
Icon=$ICON_NAME
Categories=Development;Network;
EOF

  chmod +x "$DESKTOP_FILE" 2>/dev/null || true

  if [ -d "$DESKTOP_DIR" ]; then
    local DESKTOP_SHORTCUT="$DESKTOP_DIR/TFGrid Studio Dashboard.desktop"
    cp "$DESKTOP_FILE" "$DESKTOP_SHORTCUT" 2>/dev/null || true
    chmod +x "$DESKTOP_SHORTCUT" 2>/dev/null || true
  fi

  echo ""
  log_success "TFGrid Studio Dashboard desktop launcher installed."
  echo ""
  log_info "Launcher script: $LAUNCHER_PATH"
  log_info "Menu entry: TFGrid Studio Dashboard (under Applications/Development)"
  if [ -d "$DESKTOP_DIR" ]; then
    log_info "Desktop icon: $DESKTOP_DIR/TFGrid Studio Dashboard.desktop"
  fi
  echo ""
}

_dashboard_bootstrap() {
  local home="$1"
  local TEMPLATE_DIR="$DEPLOYER_ROOT/dashboard"

  if [ -d "$TEMPLATE_DIR" ]; then
    mkdir -p "$(dirname "$home")"
    if [ ! -d "$home" ]; then
      cp -R "$TEMPLATE_DIR" "$home"
    else
      if [ -f "$TEMPLATE_DIR/server.js" ]; then
        cp "$TEMPLATE_DIR/server.js" "$home/server.js"
      fi
      if [ -d "$TEMPLATE_DIR/public" ]; then
        rm -rf "$home/public"
        cp -R "$TEMPLATE_DIR/public" "$home/public"
      fi
    fi
  else
    log_error "Dashboard template not found at $TEMPLATE_DIR"
    echo ""
    echo "Reinstall tfgrid-compose or run the dashboard from a full tfgrid-studio checkout."
    return 1
  fi
}

_dashboard_ensure_runtime() {
  local home="$1"

  if [ ! -d "$home/node_modules" ]; then
    if ! command -v npm >/dev/null 2>&1; then
      log_error "npm is required to install dashboard dependencies"
      echo "Install Node.js (v18+) and npm, then run:"
      echo "  cd $home && npm install"
      return 1
    fi

    log_info "Installing dashboard dependencies (npm install)..."
    (
      cd "$home"
      npm install
    )
  fi

  if ! command -v node >/dev/null 2>&1; then
    log_error "Node.js is required to run the dashboard backend"
    echo "Install Node.js (v18+), then run:"
    echo "  tfgrid-compose dashboard"
    return 1
  fi
}

_dashboard_start_background() {
  local home="$1"
  local server="$2"
  local pid_file="$3"
  local port_file="$4"

  if [ -f "$pid_file" ]; then
    local pid
    pid=$(cat "$pid_file" 2>/dev/null || true)
    if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
      local port=""
      if [ -f "$port_file" ]; then
        port=$(cat "$port_file" 2>/dev/null || true)
      fi
      if [ -n "$port" ]; then
        log_info "Dashboard already running at http://localhost:$port (pid $pid)"
      else
        log_info "Dashboard already running (pid $pid)"
      fi
      return 0
    else
      rm -f "$pid_file"
    fi
  fi

  log_info "Starting TFGrid Studio local dashboard in background..."
  TFGRID_DASHBOARD_PORT="${TFGRID_DASHBOARD_PORT:-43100}" \
  TFGRID_COMPOSE_BIN="${TFGRID_COMPOSE_BIN:-tfgrid-compose}" \
  TFGRID_COMMANDS_SCHEMA="$DEPLOYER_ROOT/core/commands-schema.json" \
  node "$server" >"$home/dashboard.log" 2>&1 &
  local pid=$!
  echo "$pid" >"$pid_file"

  local port=""
  for _ in $(seq 1 50); do
    if [ -f "$port_file" ]; then
      port=$(cat "$port_file" 2>/dev/null || true)
      if [ -n "$port" ]; then
        break
      fi
    fi
    sleep 0.1
  done

  if [ -z "$port" ]; then
    port="${TFGRID_DASHBOARD_PORT:-43100}"
  fi

  log_success "Dashboard started at http://localhost:$port (pid $pid)"
}

_dashboard_run_foreground() {
  local home="$1"
  local server="$2"

  log_info "Starting TFGrid Studio local dashboard..."
  echo ""
  echo "Dashboard base URL: http://localhost:${TFGRID_DASHBOARD_PORT:-43100}"
  echo ""

  TFGRID_DASHBOARD_PORT="${TFGRID_DASHBOARD_PORT:-43100}" \
  TFGRID_COMPOSE_BIN="${TFGRID_COMPOSE_BIN:-tfgrid-compose}" \
  TFGRID_COMMANDS_SCHEMA="$DEPLOYER_ROOT/core/commands-schema.json" \
  node "$server"
}
