# AI Agent Integration Guide

Complete guide for deploying and using the AI coding agent on ThreeFold Grid.

---

## Overview

The AI Agent is an AI-powered coding assistant that runs on ThreeFold Grid. It can:
- 🤖 Write and edit code autonomously
- 🔄 Run iterative improvement loops
- 🧪 Test and debug automatically
- 📝 Generate documentation
- 🔧 Refactor and optimize code

**Deployment time:** 2-3 minutes  
**Cost:** Pay-as-you-go on ThreeFold Grid  
**Access:** From your local machine via `tfgrid-compose exec`

---

## Quick Start

**Two ways to use:** Make wrapper (easier) or direct CLI (more control)

### 1. Deploy the AI Agent

**Option A: Using Make (Recommended for beginners)**
```bash
# Set your app path (do once)
export APP=../tfgrid-ai-agent

# Deploy to ThreeFold Grid
make up
```

**Option B: Using tfgrid-compose CLI directly**
```bash
# Deploy to ThreeFold Grid
tfgrid-compose up ../tfgrid-ai-agent
```

**What happens:**
1. ✅ Creates Ubuntu 24.04 VM (4 CPU, 8GB RAM, 100GB disk)
2. ✅ Configures WireGuard networking
3. ✅ Installs Node.js, Qwen CLI, and dependencies
4. ✅ Sets up git credentials
5. ✅ Configures workspace directories
6. ✅ Runs health checks

**Output:**
```
✅ 🎉 Deployment complete!
ℹ App: tfgrid-ai-agent v2.0.0
ℹ Pattern: single-vm v1.0.0
ℹ Next steps:
  • Check status: tfgrid-compose status tfgrid-ai-agent
  • View logs: tfgrid-compose logs tfgrid-ai-agent
  • Connect: tfgrid-compose ssh tfgrid-ai-agent
```

### 2. Login to Qwen AI

**Make wrapper:**
```bash
make login
```

**Direct CLI:**
```bash
# Get VM IP
VM_IP=$(cat .tfgrid-compose/state.yaml | grep '^vm_ip:' | awk '{print $2}')

# SSH with TTY for OAuth
ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$VM_IP qwen
```

Follow the OAuth prompts, copy the URL to your browser, authenticate, and press Enter.

### 3. Create Your First Project

**Make wrapper:**
```bash
make create
# Interactive - follow prompts for:
# - Project name
# - Duration
# - Prompt type
```

**Direct CLI:**
```bash
# Get VM IP
VM_IP=$(cat .tfgrid-compose/state.yaml | grep '^vm_ip:' | awk '{print $2}')

# Create interactively
ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$VM_IP \
  "cd /opt/ai-agent && /opt/ai-agent/scripts/create-project.sh"
```

### 4. Run the AI Agent Loop

**Make wrapper:**
```bash
# Run specific project
make run project=my-webapp

# Or interactive selection
make run
```

**Direct CLI:**
```bash
# Run specific project
tfgrid-compose exec ../tfgrid-ai-agent "/opt/ai-agent/scripts/run-project.sh my-webapp"

# Or interactive selection
VM_IP=$(cat .tfgrid-compose/state.yaml | grep '^vm_ip:' | awk '{print $2}')
ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$VM_IP \
  "cd /opt/ai-agent && bash scripts/interactive-wrapper.sh run"
```

### 5. Check Status & Monitor

**Make wrapper:**
```bash
# List all projects
make list

# Monitor specific project
make monitor project=my-webapp

# Stop project
make stop project=my-webapp
```

**Direct CLI:**
```bash
# List all projects
tfgrid-compose exec ../tfgrid-ai-agent /opt/ai-agent/scripts/status-projects.sh

# Monitor specific project
tfgrid-compose exec ../tfgrid-ai-agent "/opt/ai-agent/scripts/monitor-project.sh my-webapp"

# Stop project
tfgrid-compose exec ../tfgrid-ai-agent "/opt/ai-agent/scripts/stop-project.sh my-webapp"

# SSH to see files
tfgrid-compose ssh ../tfgrid-ai-agent
cd /opt/ai-agent/projects/my-webapp
ls -la
```

---

## Complete Command Reference

### Two Ways to Run Commands

Every command can be run **two ways**:

1. **Make wrapper** (shorter, needs `export APP=../tfgrid-ai-agent`)
2. **Direct CLI** (full control, no exports needed)

---

### Deployment Commands

| Action | Make Wrapper | Direct CLI |
|--------|--------------|------------|
| **Deploy** | `make up` | `tfgrid-compose up ../tfgrid-ai-agent` |
| **Status** | `make status` | `tfgrid-compose status ../tfgrid-ai-agent` |
| **SSH** | `make ssh` | `tfgrid-compose ssh ../tfgrid-ai-agent` |
| **Logs** | `make logs` | `tfgrid-compose logs ../tfgrid-ai-agent` |
| **Destroy** | `make down` | `tfgrid-compose down ../tfgrid-ai-agent` |

---

### AI Agent Commands

| Action | Make Wrapper | Direct CLI |
|--------|--------------|------------|
| **Login (one-time)** | `make login` | See login script below |
| **Create project** | `make create` | See interactive method below |
| **List projects** | `make list` | `tfgrid-compose exec ../tfgrid-ai-agent /opt/ai-agent/scripts/status-projects.sh` |
| **Run project** | `make run project=my-app` | `tfgrid-compose exec ../tfgrid-ai-agent "/opt/ai-agent/scripts/run-project.sh my-app"` |
| **Monitor** | `make monitor project=my-app` | `tfgrid-compose exec ../tfgrid-ai-agent "/opt/ai-agent/scripts/monitor-project.sh my-app"` |
| **Stop** | `make stop project=my-app` | `tfgrid-compose exec ../tfgrid-ai-agent "/opt/ai-agent/scripts/stop-project.sh my-app"` |
| **Remove** | `make remove project=my-app` | `tfgrid-compose exec ../tfgrid-ai-agent "/opt/ai-agent/scripts/remove-project.sh my-app"` |

---

### Interactive Commands (Need SSH -t)

Some commands require **interactive terminal** (`ssh -t`):

**Login to Qwen (direct CLI)**
```bash
# Get VM IP
VM_IP=$(cat .tfgrid-compose/state.yaml | grep '^vm_ip:' | awk '{print $2}')

# SSH with TTY and run qwen
ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$VM_IP qwen
```

**Create project interactively (direct CLI)**
```bash
# Get VM IP
VM_IP=$(cat .tfgrid-compose/state.yaml | grep '^vm_ip:' | awk '{print $2}')

# SSH and create
ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$VM_IP \
  "cd /opt/ai-agent && /opt/ai-agent/scripts/create-project.sh"
```

**Run project interactively (direct CLI)**
```bash
# Get VM IP  
VM_IP=$(cat .tfgrid-compose/state.yaml | grep '^vm_ip:' | awk '{print $2}')

# SSH and run with selection
ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$VM_IP \
  "cd /opt/ai-agent && bash scripts/interactive-wrapper.sh run"
```

---

### Quick CLI Scripts

**Create reusable script for direct CLI usage:**

```bash
# Save as: ~/bin/tfgrid-agent
#!/bin/bash
APP="../tfgrid-ai-agent"
VM_IP=$(cat .tfgrid-compose/state.yaml 2>/dev/null | grep '^vm_ip:' | awk '{print $2}')

case "$1" in
  list)
    tfgrid-compose exec $APP /opt/ai-agent/scripts/status-projects.sh
    ;;
  run)
    tfgrid-compose exec $APP "/opt/ai-agent/scripts/run-project.sh $2"
    ;;
  stop)
    tfgrid-compose exec $APP "/opt/ai-agent/scripts/stop-project.sh $2"
    ;;
  ssh)
    ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$VM_IP
    ;;
  *)
    echo "Usage: tfgrid-agent {list|run|stop|ssh} [project-name]"
    ;;
esac
```

Then use it:
```bash
chmod +x ~/bin/tfgrid-agent
tfgrid-agent list
tfgrid-agent run my-app
tfgrid-agent stop my-app
tfgrid-agent ssh
```

---

## Workflows

### Workflow 1: Simple Web App (Make Wrapper)

```bash
export APP=../tfgrid-ai-agent

# 1. Deploy
make up

# 2. Login (one-time)
make login

# 3. Create project
make create
# Enter: simple-blog
# Duration: 1h
# Prompt: "Create a simple blog with React and Node.js"

# 4. Agent starts automatically, or run:
make run project=simple-blog

# 5. Monitor (in another terminal)
make list
make monitor project=simple-blog

# 6. When done, check results
make ssh
cd /opt/ai-agent/projects/simple-blog
ls -la
cat README.md

# 7. Git push (if configured)
git push origin main

# 8. Stop and cleanup
make stop project=simple-blog
make down
```

### Workflow 1b: Simple Web App (Direct CLI)

```bash
# 1. Deploy
tfgrid-compose up ../tfgrid-ai-agent

# 2. Login (one-time)
VM_IP=$(cat .tfgrid-compose/state.yaml | grep '^vm_ip:' | awk '{print $2}')
ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$VM_IP qwen

# 3. Create project
ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$VM_IP \
  "cd /opt/ai-agent && /opt/ai-agent/scripts/create-project.sh"
# Enter: simple-blog, 1h, custom prompt

# 4. Run agent
tfgrid-compose exec ../tfgrid-ai-agent "/opt/ai-agent/scripts/run-project.sh simple-blog"

# 5. Monitor
tfgrid-compose exec ../tfgrid-ai-agent /opt/ai-agent/scripts/status-projects.sh
tfgrid-compose exec ../tfgrid-ai-agent "/opt/ai-agent/scripts/monitor-project.sh simple-blog"

# 6. Check results
tfgrid-compose ssh ../tfgrid-ai-agent
cd /opt/ai-agent/projects/simple-blog
ls -la

# 7. Stop and cleanup
tfgrid-compose exec ../tfgrid-ai-agent "/opt/ai-agent/scripts/stop-project.sh simple-blog"
tfgrid-compose down ../tfgrid-ai-agent
```

### Workflow 2: Code Refactoring

```bash
export APP=../tfgrid-ai-agent

# 1. Create project
make create
# Enter: refactor-project
# Prompt: "Refactor this code to use TypeScript and improve performance"

# 2. Upload your existing code
make ssh
cd /opt/ai-agent/projects/refactor-project
# Copy your files here, commit them
git add .
git commit -m "Initial code to refactor"
exit

# 3. Run agent
make run project=refactor-project

# 4. Monitor and review
make list
make monitor project=refactor-project
```

### Workflow 3: Documentation Generation

```bash
export APP=../tfgrid-ai-agent

# 1. Create docs project
make create
# Enter: api-docs
# Prompt: "Generate comprehensive documentation for this API with examples"

# 2. Run agent
make run project=api-docs

# 3. Check logs
make monitor project=api-docs

# 4. View results
make ssh
cd /opt/ai-agent/projects/api-docs
cat README.md
```

---

## Configuration

### Environment Variables

Set these on your local machine before deployment:

```bash
# Required
export TF_VAR_mnemonic=$(cat ~/.config/threefold/mnemonic)

# Optional
export QWEN_API_KEY='your-api-key'        # Qwen API key
export GITHUB_TOKEN='your-token'           # GitHub personal token
export GITEA_URL='https://gitea.example'   # Gitea URL
export GITEA_TOKEN='your-token'            # Gitea personal token
```

### Custom Resources

Edit `tfgrid-ai-agent/tfgrid-compose.yaml`:

```yaml
resources:
  cpu:
    minimum: 2
    recommended: 4     # Change this
  memory:
    minimum: 4096
    recommended: 8192  # Change this
  disk:
    minimum: 50
    recommended: 100   # Change this
```

Then redeploy:
```bash
make down && make up
```

---

## Git Integration

### Setup GitHub

```bash
# 1. Show SSH key
make exec CMD='ai-agent git-show-key'

# 2. Add to GitHub
# Copy the key and add it to https://github.com/settings/keys

# 3. Setup project with GitHub
make exec CMD='ai-agent git-setup my-project github'
```

### Setup Gitea

```bash
# 1. Show SSH key
make exec CMD='ai-agent git-show-key'

# 2. Add to your Gitea instance
# Go to Gitea → Settings → SSH Keys

# 3. Setup project with Gitea
make exec CMD='ai-agent git-setup my-project gitea'
```

### Manual Git Configuration

```bash
# SSH into VM
make ssh

# Configure git
cd /opt/ai-agent/projects/my-project
git remote add origin git@github.com:user/repo.git
git push -u origin main
```

---

## Monitoring & Logs

### Real-time Monitoring

```bash
# Watch agent progress
make exec CMD='ai-agent monitor my-project'

# View live logs
make exec CMD='ai-agent logs my-project'
```

### SSH Access

```bash
# SSH into VM
make ssh

# Check running processes
ps aux | grep ai-agent

# View project files
ls -la /opt/ai-agent/projects/

# Check system logs
journalctl -u ai-agent -f
```

### Status Overview

```bash
# All projects status
make exec CMD='ai-agent status'

# Deployment status
make status

# VM addresses
make address
```

---

## Troubleshooting

### Agent Won't Start

```bash
# Check logs
make exec CMD='ai-agent logs <project>'

# Verify Qwen login
make exec CMD='qwen whoami'

# Re-login if needed
make exec CMD='qwen login'
```

### SSH Connection Issues

```bash
# Check WireGuard
sudo wg show wg-ai-agent

# Restart WireGuard if needed
make wg

# Test connectivity
ping -c 3 $(cat .tfgrid-compose/state.yaml | grep vm_ip | awk '{print $2}')
```

### Out of Disk Space

```bash
# SSH in and check
make ssh
df -h

# Clean up old projects
ai-agent remove old-project-name

# Or increase disk size (requires redeployment)
# Edit tfgrid-compose.yaml → resources.disk
make down && make up
```

### Performance Issues

```bash
# Check resource usage
make ssh
htop

# Consider upgrading resources
# Edit tfgrid-compose.yaml
# Increase CPU/memory
make down && make up
```

---

## Best Practices

### 1. Project Organization

```bash
# Use descriptive names
ai-agent create webapp-dashboard  # Good
ai-agent create test1             # Bad

# One project per goal
ai-agent create frontend-app
ai-agent create backend-api
# Not: ai-agent create fullstack-everything
```

### 2. Prompts

**Good prompts:**
- "Create a REST API with Express.js and PostgreSQL for a todo app"
- "Refactor this code to use async/await instead of callbacks"
- "Add comprehensive error handling and logging"

**Bad prompts:**
- "Make it better" (too vague)
- "Build everything" (too broad)
- "Fix bugs" (which bugs?)

### 3. Monitoring

```bash
# Always monitor long-running tasks
make exec CMD='ai-agent run big-project' &
make exec CMD='ai-agent monitor big-project'
```

### 4. Git Workflow

```bash
# Setup git first
make exec CMD='ai-agent git-setup project github'

# Agent will auto-commit
# Review before pushing
make ssh
cd /opt/ai-agent/projects/project
git log
git diff
git push
```

### 5. Resource Management

```bash
# Stop projects when not needed
make exec CMD='ai-agent stopall'

# Remove completed projects
make exec CMD='ai-agent remove old-project'

# Destroy VM when not in use
make down
```

---

## Advanced Usage

### Multiple Projects

```bash
# Create and run multiple projects
make exec CMD='ai-agent create frontend'
make exec CMD='ai-agent create backend'
make exec CMD='ai-agent create docs'

make exec CMD='ai-agent run frontend' &
make exec CMD='ai-agent run backend' &
make exec CMD='ai-agent run docs' &

# Monitor all
make exec CMD='ai-agent status'
```

### Custom Agent Scripts

```bash
# SSH in
make ssh

# Create custom script
cat > /opt/ai-agent/custom-agent.sh << 'EOF'
#!/bin/bash
ai-agent create "$1"
ai-agent run "$1" &
ai-agent monitor "$1"
EOF

chmod +x /opt/ai-agent/custom-agent.sh

# Use it
/opt/ai-agent/custom-agent.sh my-new-project
```

### Scheduled Runs

```bash
# SSH in and setup cron
make ssh
crontab -e

# Add scheduled agent runs
0 2 * * * ai-agent run nightly-refactor
0 9 * * * ai-agent run morning-docs
```

---

## FAQ

**Q: Can I run multiple agents simultaneously?**  
A: Yes! Each project runs independently. Use `ai-agent status` to see all.

**Q: How much does it cost?**  
A: Depends on ThreeFold Grid pricing. Typically $10-30/month for a 4CPU/8GB VM.

**Q: Can I access from multiple machines?**  
A: Yes, deploy once and use `tfgrid-compose exec` from any machine with access.

**Q: What if my local machine disconnects?**  
A: Agent keeps running on the VM. Reconnect anytime with `make exec`.

**Q: Can I use my own AI API keys?**  
A: Yes, set `QWEN_API_KEY` before deployment or SSH in and configure.

**Q: How do I backup projects?**  
A: SSH in and copy `/opt/ai-agent/projects/` or use git push.

**Q: Can I upgrade the agent version?**  
A: Yes, `make down` then `make up` with updated tfgrid-ai-agent repo.

---

## Next Steps

- **Try it:** Deploy and create your first project
- **Explore:** Test different prompts and workflows
- **Share:** Push your projects to GitHub/Gitea
- **Scale:** Deploy multiple instances for different teams

**Need help?** 
- Check logs: `make exec CMD='ai-agent logs <project>'`
- SSH debug: `make ssh`
- Community: https://forum.threefold.io

---

**Ready to code with AI on ThreeFold Grid!** 🚀
