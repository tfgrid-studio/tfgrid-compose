# Command Shortcuts

**Version:** 0.12.0  
**Status:** ✅ Production Ready

---

## Overview

TFGrid Compose supports custom command shortcuts to save typing. Instead of typing `tfgrid-compose` every time, create shorter aliases like `tfgrid`, `tf`, or `grid`.

---

## Quick Start

### Default Shortcut (Auto-Created)

The `tfgrid` shortcut is automatically created during installation:

```bash
make install
# ✅ Created shortcut: tfgrid -> tfgrid-compose

# Use it immediately
tfgrid --version
tfgrid up
tfgrid status
```

### Interactive Mode (Recommended)

Simply run without arguments for an interactive menu:

```bash
tfgrid-compose shortcut

🔗 Shortcut Management (Interactive)

Current shortcuts:
  • tfgrid

What would you like to do?
  1) Create a new shortcut
  2) Remove a shortcut
  3) List all shortcuts (detailed)
  4) Reset to default (tfgrid)
  5) Exit

Enter choice [1-5]: 1

Popular choices: tf, grid, tfc
Enter shortcut name: tf

✅ Created shortcut: tf
```

### Create Custom Shortcuts (Direct)

```bash
# Create directly without interactive mode
tfgrid-compose shortcut tf

# Now use it
tf up
tf status
tf ssh

# Create another one
tfgrid-compose shortcut grid
grid logs
```

---

## Commands

### Interactive Mode (No Arguments)

```bash
tfgrid-compose shortcut
```

**Interactive menu with options:**
1. Create a new shortcut
2. Remove a shortcut
3. List all shortcuts (detailed)
4. Reset to default (tfgrid)
5. Exit

**Example session:**
```bash
$ tfgrid-compose shortcut

🔗 Shortcut Management (Interactive)

Current shortcuts:
  • tfgrid

What would you like to do?
  1) Create a new shortcut
  2) Remove a shortcut
  3) List all shortcuts (detailed)
  4) Reset to default (tfgrid)
  5) Exit

Enter choice [1-5]: 1

Popular choices: tf, grid, tfc
Enter shortcut name: tf

✅ Created shortcut: tf

ℹ You can now use: tf <command>
```

### Create Shortcut (Direct)

```bash
tfgrid-compose shortcut <name>
```

**Example:**
```bash
tfgrid-compose shortcut tf
# ✅ Created shortcut: tf
# ℹ You can now use: tf <command>
```

### List Shortcuts

```bash
tfgrid-compose shortcut --list
# or
tfgrid-compose shortcut -l
```

**Output:**
```
🔗 Active shortcuts:

  • tfgrid -> tfgrid-compose
  • tf -> tfgrid-compose
  • grid -> tfgrid-compose
```

### Remove Shortcut

```bash
tfgrid-compose shortcut --remove <name>
# or
tfgrid-compose shortcut -r <name>
```

**Example:**
```bash
tfgrid-compose shortcut --remove tf
# ✅ Removed shortcut: tf
```

### Reset to Default

```bash
tfgrid-compose shortcut --default
# or
tfgrid-compose shortcut -d
```

This ensures the `tfgrid` shortcut exists.

---

## How It Works

### Implementation

Shortcuts are **symlinks** in `~/.local/bin/` that point to `tfgrid-compose`:

```bash
~/.local/bin/tfgrid -> ~/.local/bin/tfgrid-compose
~/.local/bin/tf -> ~/.local/bin/tfgrid-compose
```

### Benefits of Symlinks

- ✅ Works in all shells (bash, zsh, fish)
- ✅ No shell-specific aliases needed
- ✅ Survives shell restarts
- ✅ Works in scripts and automation
- ✅ Easy to manage and remove

---

## Popular Shortcut Names

Users commonly choose:

| Shortcut | Length | Use Case |
|----------|--------|----------|
| `tfgrid` | 7 chars | Default, clear & professional |
| `tf` | 2 chars | Ultra-short for power users |
| `grid` | 4 chars | Concise and memorable |
| `tfc` | 3 chars | Abbreviation-style |
| `compose` | 7 chars | Docker Compose familiarity |

**Recommendation:** Start with `tfgrid` (default), add `tf` if you want shorter.

---

## Examples

### Daily Workflow with Shortcuts

```bash
# Create your preferred shortcut
tfgrid-compose shortcut tf

# Use it for everything
tf login
tf search ai
tf up tfgrid-ai-agent
tf status
tf create
tf run my-project
tf logs
tf down
```

### Multiple Shortcuts

```bash
# Create multiple for different contexts
tfgrid-compose shortcut tfgrid    # Professional
tfgrid-compose shortcut tf         # Quick
tfgrid-compose shortcut grid       # Alternative

# Use whatever feels right at the moment
tfgrid up              # Full name
tf status              # Quick check
grid logs              # Different mood
```

---

## Installation Behavior

### During Install

```bash
make install
```

Output:
```
📦 Installing tfgrid-compose...
✅ Installed to ~/.local/bin/tfgrid-compose

🔗 Creating default shortcut...
✅ Created shortcut: tfgrid -> tfgrid-compose

✅ Installation complete!

💡 You can now use either command:
   • tfgrid-compose  (full name)
   • tfgrid          (shortcut)

To create a custom shortcut: tfgrid-compose shortcut <name>

🧪 Test with: tfgrid --version
```

### During Uninstall

```bash
make uninstall
```

Automatically removes:
- Main command: `tfgrid-compose`
- All shortcuts: `tfgrid`, `tf`, `grid`, etc.

---

## Validation Rules

Shortcut names must:
- ✅ Start with a letter
- ✅ Contain only letters, numbers, hyphens, underscores
- ❌ Cannot be `tfgrid-compose` (main command)
- ❌ Cannot conflict with existing files in `~/.local/bin/`

**Valid:**
```bash
tfgrid-compose shortcut tf        ✅
tfgrid-compose shortcut grid      ✅
tfgrid-compose shortcut my-tfc    ✅
tfgrid-compose shortcut deploy_1  ✅
```

**Invalid:**
```bash
tfgrid-compose shortcut 123       ❌ (starts with number)
tfgrid-compose shortcut my@app    ❌ (contains @)
tfgrid-compose shortcut tfgrid-compose  ❌ (main command)
```

---

## Troubleshooting

### Shortcut Not Working

**Problem:** Shortcut command not found

**Solutions:**

1. **Check PATH includes `~/.local/bin`:**
   ```bash
   echo $PATH | grep ".local/bin"
   ```

2. **Reload shell:**
   ```bash
   # Bash/Zsh
   source ~/.bashrc  # or ~/.zshrc
   
   # Fish
   source ~/.config/fish/config.fish
   ```

3. **Verify shortcut exists:**
   ```bash
   ls -la ~/.local/bin/tfgrid
   tfgrid-compose shortcut --list
   ```

### Shortcut Points to Wrong Location

**Problem:** Shortcut exists but doesn't work

**Solution:**
```bash
# Remove and recreate
tfgrid-compose shortcut --remove tfgrid
tfgrid-compose shortcut tfgrid
```

### Cannot Remove Shortcut

**Problem:** "Not a tfgrid-compose shortcut"

**Cause:** The file exists but isn't a symlink to tfgrid-compose

**Solution:**
```bash
# Manually check what it points to
ls -la ~/.local/bin/your-shortcut

# Remove manually if needed
rm ~/.local/bin/your-shortcut
```

---

## Advanced Usage

### Shortcuts in Scripts

Shortcuts work in scripts:

```bash
#!/usr/bin/env bash
# deploy.sh

# Use shortcut in automation
tf up my-app
tf status my-app
```

### Team Conventions

Establish team standards:

```bash
# .team-setup.sh
echo "Setting up standard shortcuts..."
tfgrid-compose shortcut tf
tfgrid-compose shortcut grid
```

### Conditional Shortcuts

```bash
# Only create if doesn't exist
if ! command -v tf &> /dev/null; then
    tfgrid-compose shortcut tf
fi
```

---

## Comparison with Aliases

### Symlinks (Our Approach) ✅

```bash
tfgrid-compose shortcut tf
```

**Pros:**
- Works in all shells
- Survives restarts
- Works in scripts
- Single source of truth

**Cons:**
- Requires write access to `~/.local/bin`

### Shell Aliases (Alternative) ❌

```bash
# Fish
alias tf='tfgrid-compose'

# Bash/Zsh
alias tf='tfgrid-compose'
```

**Pros:**
- No file system changes

**Cons:**
- Shell-specific syntax
- Doesn't work in scripts
- Needs to be added to each shell config
- Lost if config is reset

**Our choice:** Symlinks for universal compatibility.

---

## Migration from Old Setup

If you were using aliases:

```bash
# Remove old aliases from shell config
# Edit ~/.bashrc, ~/.zshrc, or ~/.config/fish/config.fish

# Create proper shortcuts
tfgrid-compose shortcut tf
tfgrid-compose shortcut grid

# Verify
tfgrid-compose shortcut --list
```

---

## Related Documentation

- [Installation Guide](QUICKSTART.md)
- [CLI Reference](../README.md#basic-commands)
- [Context Files](CONTEXT_FILE_USAGE.md)

---

**Last Updated:** 2025-10-18  
**Version:** 0.12.0
