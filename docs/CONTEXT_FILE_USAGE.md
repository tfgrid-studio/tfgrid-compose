# Context File Usage Guide

**Status:** ✅ Implemented in v1.0.0  
**Priority:** HIGH  

---

## Overview

Context file support makes tfgrid-compose as user-friendly as docker-compose!

**Before (verbose):**
```bash
tfgrid-compose exec ../tfgrid-ai-agent "/opt/ai-agent/scripts/run-project.sh my-app"
```

**After (simple):**
```bash
tfgrid-compose run my-app
```

---

## Setup (One Time)

Create `.tfgrid-compose.yaml` in your project directory:

```bash
echo "app: ../tfgrid-ai-agent" > .tfgrid-compose.yaml
```

That's it! Now all commands know which app to use.

---

## New Commands

### App-Specific Commands

```bash
# List all projects
tfgrid-compose projects

# Create new project (interactive)
tfgrid-compose create

# Run project
tfgrid-compose run my-project

# Or interactive selection
tfgrid-compose run

# Monitor project
tfgrid-compose monitor my-project

# Stop project
tfgrid-compose stop my-project

# Remove project
tfgrid-compose remove my-project
```

### Standard Commands (Now Shorter!)

```bash
# Deploy (uses context)
tfgrid-compose up

# Status
tfgrid-compose status

# SSH
tfgrid-compose ssh

# Logs
tfgrid-compose logs

# Destroy
tfgrid-compose down
```

---

## Complete Workflow

```bash
# 1. Create context file (once)
echo "app: ../tfgrid-ai-agent" > .tfgrid-compose.yaml

# 2. Deploy
tfgrid-compose up

# 3. Create project
tfgrid-compose create

# 4. Run agent
tfgrid-compose run my-project

# 5. Monitor
tfgrid-compose projects
tfgrid-compose monitor my-project

# 6. Stop
tfgrid-compose stop my-project

# 7. Cleanup
tfgrid-compose down
```

---

## Context File Format

```yaml
# Required
app: ../tfgrid-ai-agent

# Future: Optional settings
# defaults:
#   network: wireguard
#   region: default
```

---

## Backward Compatibility

✅ Old commands still work!

```bash
# These all still work
tfgrid-compose up ../tfgrid-ai-agent
tfgrid-compose status ../tfgrid-ai-agent
tfgrid-compose down ../tfgrid-ai-agent
```

---

## Tips

1. **Add to .gitignore** - Context file is user-specific (already done)
2. **Override when needed** - Explicit app path overrides context
3. **One context per directory** - Each project can have its own

---

## Make Wrapper Still Works

The Makefile wrapper is still available if you prefer:

```bash
export APP=../tfgrid-ai-agent
make up
make login
make create
make list
make down
```

Choose whichever style you prefer!

---

**This is production-ready and following industry standards!** 🎯
