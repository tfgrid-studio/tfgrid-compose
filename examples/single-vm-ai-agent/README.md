# AI Agent Example - Single VM Pattern

**Deploy a complete AI agent development environment on ThreeFold Grid**

## Overview

This example demonstrates deploying an AI-powered development agent on a single VM using the `single-vm` pattern. The AI agent can create, modify, and manage software projects autonomously.

## What Gets Deployed

- **Base System**: Ubuntu 24.04 with minimal setup (from pattern)
- **Node.js 20**: JavaScript runtime (LTS version)
- **Qwen CLI**: AI code generation tool
- **AI Agent**: Complete agent setup with project management
- **Git Configuration**: Ready for code versioning
- **Development Tools**: Build tools, Python, jq, tmux, etc.

## Architecture

```
single-vm pattern (generic)
└── Ansible playbook (example-specific)
    ├── Install Node.js & Qwen
    ├── Clone AI agent repository
    ├── Configure git & SSH keys
    └── Setup workspace
```

## Prerequisites

1. **ThreeFold Grid Account**
   - Mnemonic configured in `~/.config/threefold/mnemonic`
   - TFT credits (~20 TFT minimum)

2. **Node Selection**
   - Replace `nodes.vm: 1` with actual node ID
   - Find nodes: https://dashboard.grid.tf/

3. **Optional Environment Variables**
   ```bash
   export GIT_USER_NAME="Your Name"
   export GIT_USER_EMAIL="you@example.com"
   export QWEN_API_KEY="your-key"  # Optional
   export GITHUB_TOKEN="ghp_..."    # Optional
   ```

## Quick Start

### 1. Update Configuration

Edit `tfgrid-compose.yaml`:
```yaml
nodes:
  vm: YOUR_NODE_ID  # Replace with actual node ID
```

### 2. Deploy

```bash
cd examples/single-vm-ai-agent
tfgrid-compose up .
```

**Deployment time:** ~3-5 minutes

### 3. Access AI Agent

```bash
# SSH into the VM
tfgrid-compose ssh .

# Inside VM: Run AI agent
cd /opt/ai-agent
./scripts/run.sh

# Create a new project
./scripts/create-project.sh my-website
```

## What This Example Shows

1. **Pattern Reusability**: Generic `single-vm` pattern + specific setup via Ansible
2. **Ansible Deployment**: Using `deployment/playbook.yml` instead of bash hooks
3. **Complex Setup**: Multi-step installation (Node.js, NPM packages, git config)
4. **Environment Variables**: Passing configuration from host to deployment

## Resources

- **CPU**: 4 cores (AI requires computation)
- **Memory**: 8GB (for model processing)
- **Disk**: 100GB (for projects and dependencies)
- **Network**: WireGuard (private, secure)

## Comparison with Simple Website Example

| Aspect | Simple Website | AI Agent |
|--------|----------------|----------|
| Pattern | single-vm | single-vm |
| Deployment | Bash hooks | Ansible playbook |
| Complexity | Low (nginx only) | High (Node.js, Qwen, git) |
| Resources | 2 CPU, 2GB | 4 CPU, 8GB |
| Use Case | Static content | Development agent |

## Next Steps

After deployment:

1. **Add SSH Key to GitHub**
   - Deployment outputs SSH public key
   - Add to GitHub: Settings → SSH Keys

2. **Create Projects**
   ```bash
   cd /opt/ai-agent
   ./scripts/create-project.sh portfolio-site
   # AI builds complete website
   ```

3. **Deploy Projects** (Advanced)
   ```bash
   # From inside AI agent VM, deploy to gateway pattern!
   cd /opt/ai-agent-projects/portfolio-site
   tfgrid-compose up . --pattern=gateway --domain=mysite.com
   ```

## Scaling Up

This single-VM AI agent can:
- **Deploy gateway apps**: Build AND deploy web apps
- **Manage multiple projects**: Workspace in `/opt/ai-agent-projects/`
- **Auto-push to git**: Configured git credentials
- **Scale deployments**: Use tfgrid-compose from within VM

## Troubleshooting

**Node.js installation fails:**
- Check internet connectivity on VM
- Retry: `tfgrid-compose up .` is idempotent

**Qwen CLI errors:**
- Qwen uses OAuth by default (no API key needed)
- API key only for enterprise/paid features

**Git push fails:**
- Add SSH key to GitHub (shown in deployment output)
- Or use GITHUB_TOKEN environment variable

## Related Examples

- **simple-vm**: Basic website with nginx
- **gateway-ssl**: Production web app with HTTPS
- **k3s-cluster**: Kubernetes cluster

## Architecture Note

This example demonstrates how specific applications (AI agent) use the generic `single-vm` pattern. The pattern provides the VM infrastructure, while the application (via Ansible playbook) adds the specific software stack.

**Pattern Philosophy:**
```
Generic Pattern (minimal) + Application-Specific Setup = Complete Deployment
```

## See Also

- Full AI Agent Repo: `externals/tfgrid-ai-agent` (standalone)
- Single-VM Pattern: `patterns/single-vm/README.md`
- TFGrid Compose Docs: `docs/QUICKSTART.md`
