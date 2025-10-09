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

### 1. Deploy the AI Agent

```bash
# Set your app path (do once)
export APP=../tfgrid-ai-agent

# Deploy to ThreeFold Grid
make up
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

```bash
# Interactive login (from your local machine!)
make exec CMD='qwen login'
```

This opens a browser for authentication. Follow the prompts.

### 3. Create Your First Project

```bash
# Create a new coding project
make exec CMD='ai-agent create my-webapp'

# Or interactive mode
make exec CMD='ai-agent create'
# Then follow prompts
```

### 4. Run the AI Agent Loop

```bash
# Start autonomous coding loop
make exec CMD='ai-agent run my-webapp'

# Monitor progress
make exec CMD='ai-agent monitor my-webapp'

# View logs
make exec CMD='ai-agent logs my-webapp'
```

### 5. Check Results

```bash
# List all projects
make exec CMD='ai-agent list'

# Show project summary
make exec CMD='ai-agent summary my-webapp'

# SSH in to see files directly
make ssh
cd /opt/ai-agent/projects/my-webapp
ls -la
```

---

## Complete Command Reference

### Deployment Commands

```bash
# Deploy
make up APP=../tfgrid-ai-agent
tfgrid-compose up ../tfgrid-ai-agent

# Check status
make status
tfgrid-compose status ../tfgrid-ai-agent

# Destroy
make down
tfgrid-compose down ../tfgrid-ai-agent
```

### AI Agent Commands

All commands execute on the deployed VM from your local machine:

```bash
# Authentication
make exec CMD='qwen login'           # Login to Qwen AI
make exec CMD='qwen logout'          # Logout

# Project Management
make exec CMD='ai-agent create <name>'      # Create new project
make exec CMD='ai-agent list'               # List all projects
make exec CMD='ai-agent remove <name>'      # Delete project

# Running Agent
make exec CMD='ai-agent run <name>'         # Start coding loop
make exec CMD='ai-agent monitor <name>'     # Watch progress
make exec CMD='ai-agent stop <name>'        # Stop agent
make exec CMD='ai-agent restart <name>'     # Restart agent
make exec CMD='ai-agent stopall'            # Stop all projects

# Logs & Status
make exec CMD='ai-agent logs <name>'        # View project logs
make exec CMD='ai-agent summary <name>'     # Show summary
make exec CMD='ai-agent status'             # Status of all projects

# Git Integration
make exec CMD='ai-agent git-setup <name> github'     # Setup GitHub
make exec CMD='ai-agent git-setup <name> gitea'      # Setup Gitea
make exec CMD='ai-agent git-show-key'                # Show SSH key
```

### Using CLI Directly

```bash
# Same commands work with CLI
tfgrid-compose exec ../tfgrid-ai-agent qwen login
tfgrid-compose exec ../tfgrid-ai-agent ai-agent create my-app
tfgrid-compose exec ../tfgrid-ai-agent ai-agent run my-app
```

---

## Workflows

### Workflow 1: Simple Web App

```bash
export APP=../tfgrid-ai-agent

# 1. Deploy
make up

# 2. Login
make exec CMD='qwen login'

# 3. Create project
make exec CMD='ai-agent create simple-blog'
# Prompt: "Create a simple blog with React and Node.js"

# 4. Start agent
make exec CMD='ai-agent run simple-blog'

# 5. Monitor (in another terminal)
make exec CMD='ai-agent monitor simple-blog'

# 6. When done, check results
make ssh
cd /opt/ai-agent/projects/simple-blog
ls -la
cat README.md

# 7. Git push (if configured)
git push origin main

# 8. Cleanup
make down
```

### Workflow 2: Code Refactoring

```bash
# 1. Create project with existing code
make exec CMD='ai-agent create refactor-project'

# 2. Upload your code
make ssh
cd /opt/ai-agent/projects/refactor-project
# Copy your files here

# 3. Run agent with refactoring prompt
make exec CMD='ai-agent run refactor-project'
# Prompt: "Refactor this code to use TypeScript and improve performance"

# 4. Monitor and review
make exec CMD='ai-agent monitor refactor-project'
```

### Workflow 3: Documentation Generation

```bash
# Create and run for documentation
make exec CMD='ai-agent create my-docs'
# Prompt: "Generate comprehensive documentation for this API"

make exec CMD='ai-agent run my-docs'
make exec CMD='ai-agent logs my-docs'
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
export GITEA_TOKEN='your-token'            # Gitea token
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
