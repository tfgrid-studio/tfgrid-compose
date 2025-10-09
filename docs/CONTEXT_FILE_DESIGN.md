# Context File Design

**Status:** Planned for v1.0.0  
**Priority:** HIGH  
**Complexity:** Low (~100 lines of code)

---

## Problem

Current commands are too verbose:
```bash
tfgrid-compose exec ../tfgrid-ai-agent "/opt/ai-agent/scripts/run-project.sh my-app"
```

Users must specify the app path every single time.

---

## Solution: Context File

Like Docker Compose, Kubernetes, Terraform - auto-detect app from context.

### User Experience

**1. Create context file (once)**
```bash
# In your project directory
cat > .tfgrid-compose.yaml << EOF
app: ../tfgrid-ai-agent
EOF
```

**2. Commands become simple**
```bash
tfgrid-compose agent list
tfgrid-compose agent run my-app
tfgrid-compose agent create
tfgrid-compose agent stop my-app
```

---

## Context File Format

**Location:** `.tfgrid-compose.yaml` in current directory

**Format:**
```yaml
# Required
app: ../tfgrid-ai-agent

# Optional
defaults:
  network: wireguard  # or mycelium
  region: default
  
# Optional environment vars
env:
  PROJECT_ENV: production
```

---

## Implementation

### 1. Context Detection Function

Add to `cli/tfgrid-compose`:

```bash
# Load context from .tfgrid-compose.yaml if it exists
load_context() {
    local context_file=".tfgrid-compose.yaml"
    
    if [ -f "$context_file" ]; then
        # Parse YAML (simple grep approach)
        APP_FROM_CONTEXT=$(grep '^app:' "$context_file" | sed 's/app: *//' | tr -d '"' | tr -d "'")
        
        if [ -n "$APP_FROM_CONTEXT" ]; then
            echo "ℹ Using app from context: $APP_FROM_CONTEXT" >&2
            echo "$APP_FROM_CONTEXT"
            return 0
        fi
    fi
    
    return 1
}
```

### 2. Modify Command Functions

```bash
# Before
cmd_up() {
    local app_path="$1"
    if [ -z "$app_path" ]; then
        echo "❌ Error: APP not specified"
        exit 1
    fi
    # ... rest
}

# After
cmd_up() {
    local app_path="$1"
    
    # Try context if no arg provided
    if [ -z "$app_path" ]; then
        app_path=$(load_context) || {
            echo "❌ Error: APP not specified and no context file found"
            echo "Create .tfgrid-compose.yaml or specify app path"
            exit 1
        }
    fi
    # ... rest
}
```

### 3. Add `agent` Subcommand

```bash
# New command: tfgrid-compose agent <action>
cmd_agent() {
    local action="$1"
    shift
    
    # Load context
    local app_path=$(load_context) || {
        echo "❌ Error: No context file found"
        echo "Create .tfgrid-compose.yaml with 'app: <path>'"
        exit 1
    }
    
    # Load app to get VM IP
    load_application "$app_path"
    local vm_ip=$(get_vm_ip)
    
    case "$action" in
        list)
            exec_on_vm "$vm_ip" "/opt/ai-agent/scripts/status-projects.sh"
            ;;
        run)
            local project="$1"
            if [ -z "$project" ]; then
                ssh -t root@$vm_ip "cd /opt/ai-agent && bash scripts/interactive-wrapper.sh run"
            else
                exec_on_vm "$vm_ip" "/opt/ai-agent/scripts/run-project.sh $project"
            fi
            ;;
        create)
            ssh -t root@$vm_ip "cd /opt/ai-agent && /opt/ai-agent/scripts/create-project.sh"
            ;;
        stop)
            local project="$1"
            if [ -z "$project" ]; then
                ssh -t root@$vm_ip "cd /opt/ai-agent && bash scripts/interactive-wrapper.sh stop"
            else
                exec_on_vm "$vm_ip" "/opt/ai-agent/scripts/stop-project.sh $project"
            fi
            ;;
        monitor)
            local project="$1"
            if [ -z "$project" ]; then
                ssh -t root@$vm_ip "cd /opt/ai-agent && bash scripts/interactive-wrapper.sh monitor"
            else
                exec_on_vm "$vm_ip" "/opt/ai-agent/scripts/monitor-project.sh $project"
            fi
            ;;
        *)
            echo "Usage: tfgrid-compose agent {list|run|create|stop|monitor} [project]"
            exit 1
            ;;
    esac
}
```

### 4. Update Main Dispatcher

```bash
case "$command" in
    # Existing commands
    up|down|status|ssh|logs|exec|patterns|init|address)
        "cmd_$command" "$@"
        ;;
    # New agent command
    agent)
        cmd_agent "$@"
        ;;
    *)
        show_help
        exit 1
        ;;
esac
```

---

## Backward Compatibility

✅ **Fully backward compatible**
- Old way still works: `tfgrid-compose up ../tfgrid-ai-agent`
- New way optional: `tfgrid-compose up` (with context file)
- No breaking changes

---

## Usage Examples

### With Context File

```bash
# Setup (once)
cat > .tfgrid-compose.yaml << EOF
app: ../tfgrid-ai-agent
EOF

# Use short commands
tfgrid-compose up
tfgrid-compose agent list
tfgrid-compose agent run my-project
tfgrid-compose agent create
tfgrid-compose ssh
tfgrid-compose down
```

### Without Context File (Old Way)

```bash
# Still works!
tfgrid-compose up ../tfgrid-ai-agent
tfgrid-compose exec ../tfgrid-ai-agent "command"
tfgrid-compose down ../tfgrid-ai-agent
```

### Override Context

```bash
# Context says: app: ../tfgrid-ai-agent
# But you can override:
tfgrid-compose up ../other-app
```

---

## Benefits

1. ✅ **User Friendly** - Short, memorable commands
2. ✅ **Industry Standard** - Matches docker-compose, kubectl patterns
3. ✅ **Easy to Implement** - ~100 lines of code
4. ✅ **Backward Compatible** - No breaking changes
5. ✅ **Reduces Errors** - Less typing = fewer mistakes
6. ✅ **Better DX** - Developer experience improvement

---

## Rollout Plan

### Phase 1: Context Detection (v1.0)
- Add `load_context()` function
- Update all commands to check for context
- Add `.tfgrid-compose.yaml` to .gitignore templates

### Phase 2: Agent Subcommand (v1.0)
- Add `cmd_agent()` function
- Implement all agent actions
- Update documentation

### Phase 3: Enhanced Context (v1.1)
- Add default settings support
- Environment variable injection
- Multi-app contexts

---

## Testing

```bash
# Test with context
echo "app: ../tfgrid-ai-agent" > .tfgrid-compose.yaml
tfgrid-compose up
tfgrid-compose agent list

# Test without context
rm .tfgrid-compose.yaml
tfgrid-compose up ../tfgrid-ai-agent  # Should still work

# Test override
echo "app: ../tfgrid-ai-agent" > .tfgrid-compose.yaml
tfgrid-compose up ../other-app  # Should use other-app
```

---

## Estimated Effort

- **Context detection:** 1-2 hours
- **Agent subcommand:** 2-3 hours
- **Testing:** 1 hour
- **Documentation:** 1 hour

**Total:** ~1 day of focused work

---

**This is the RIGHT solution for v1.0!** 🎯
