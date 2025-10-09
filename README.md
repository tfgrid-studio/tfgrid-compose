# TFGrid Compose

**Universal deployment orchestrator for ThreeFold Grid applications.**

> **Note:** This repository was renamed from `tfgrid-deployer` to `tfgrid-compose` on Oct 9, 2025 as part of the TFGrid Studio rebrand.

[![Status](https://img.shields.io/badge/status-production--ready-green)]() 
[![Version](https://img.shields.io/badge/version-2.0.0-blue)]() 
[![Patterns](https://img.shields.io/badge/patterns-3%2F3-success)]()
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)]()

## Overview

TFGrid Compose is a production-ready deployment platform that makes deploying applications on ThreeFold Grid as simple as `tfgrid-compose up`.

**Key Features:**
- ✅ **One-command deployment** - From zero to running app in 2-3 minutes
- ✅ **Context file support** - Set app once, use short commands everywhere
- ✅ **Agent subcommand** - Simple AI agent management (`tfgrid-compose agent list`)
- ✅ **Auto-install** - Automatically sets up PATH in your shell
- ✅ **Multiple patterns** - single-vm, gateway, k3s (coming soon)
- ✅ **Smart validation** - Checks prerequisites and prevents errors
- ✅ **Remote execution** - Run commands on deployed VMs from your local machine
- ✅ **State management** - Tracks all deployments automatically
- ✅ **Idempotency** - Safe to retry, prevents duplicate deployments

## Structure

```
tfgrid-deployer/
├── cli/                     # tfgrid-compose CLI tool
├── core/                    # Core orchestration logic
├── patterns/                # Deployment patterns
│   └── single-vm/           # Single VM pattern (MVP)
├── lib/                     # Shared modules and roles
└── docs/                    # Documentation
```

## Current Status

**🎉 COMPLETE FIRST LAYER - v2.0.0**

All 3 core deployment patterns are production-ready!

### v1.0 Features ✅
- [x] Full deployment orchestration (Terraform + WireGuard + Ansible)
- [x] Context file support (`.tfgrid-compose.yaml`)
- [x] Agent subcommand for AI agent management
- [x] Automatic PATH setup during installation
- [x] Input validation and error handling
- [x] Idempotency protection
- [x] Remote command execution (`exec`)
- [x] Comprehensive documentation
- [x] Auto-install with `make install`
- [x] Single-VM pattern (fully tested)

### All 3 Core Patterns Complete! ✅
- [x] **Single-VM pattern** - Development, databases, AI agents
- [x] **Gateway pattern** - Production web apps with public IPv4, SSL, load balancing
- [x] **K3s pattern** - Kubernetes clusters for cloud-native apps

### Coming Soon 🚧
- [ ] Automated test suite
- [ ] Shell completion (bash/zsh/fish)
- [ ] Video tutorials
- [ ] Web dashboard

## Patterns

### single-vm ✅ **Production Ready**

Single VM deployment with Wireguard and Mycelium networking.

**Use cases:**
- Development environments
- Databases (PostgreSQL, MongoDB, Redis)
- Internal services
- AI agents
- Background workers

**Documentation:** [patterns/single-vm/](patterns/single-vm/)

---

### gateway ✅ **Production Ready**

Gateway VM with public IPv4 + backend VMs with private networking.

**Use cases:**
- Production web applications
- E-commerce sites
- Multi-tier applications
- Public-facing services

**Features:**
- Public IPv4 on gateway
- Nginx/HAProxy reverse proxy
- Free SSL/TLS (Let's Encrypt)
- Load balancing & health checks
- Private backend network
- Network redundancy (WireGuard + Mycelium)

**Documentation:** [patterns/gateway/README.md](patterns/gateway/README.md)

---

### k3s ✅ **Production Ready**

Kubernetes cluster (K3s) with control plane, workers, and management node.

**Use cases:**
- Cloud-native applications
- Microservices architectures
- Production SaaS platforms
- High availability requirements

**Features:**
- Lightweight Kubernetes (K3s)
- MetalLB load balancer
- Nginx Ingress Controller
- Management node with kubectl, helm, k9s
- Local-path storage provisioner
- HA control plane support

**Documentation:** [patterns/k3s/README.md](patterns/k3s/README.md)

## Quick Start

### 1. Install

```bash
# Setup standard workspace
mkdir -p ~/code/github.com/tfgrid-studio
cd ~/code/github.com/tfgrid-studio

# Clone repositories
git clone https://github.com/tfgrid-studio/tfgrid-compose
git clone https://github.com/tfgrid-studio/tfgrid-ai-agent

# Install (auto-configures PATH)
cd tfgrid-deployer
make install
```

This automatically adds `tfgrid-compose` to your PATH!

**Note:** We use `~/code/github.com/{org}/{repo}` as the standard workspace structure. See [WORKSPACE_STANDARD.md](../WORKSPACE_STANDARD.md) for details.

**Prerequisites:**
- Terraform or OpenTofu
- Ansible
- WireGuard (for private networking)
- ThreeFold Grid account with mnemonic

See [Quick Start Guide](docs/QUICKSTART.md) for detailed setup.

### 2. Configure

```bash
# Store your mnemonic
mkdir -p ~/.config/threefold
echo "your twelve word mnemonic" > ~/.config/threefold/mnemonic
chmod 600 ~/.config/threefold/mnemonic

# Create context file (optional but recommended)
echo "app: ../tfgrid-ai-agent" > .tfgrid-compose.yaml
```

### 3. Deploy & Use

```bash
# Deploy application (uses context)
tfgrid-compose up

# Use AI agent with simple commands
tfgrid-compose agent list
tfgrid-compose agent create
tfgrid-compose agent run my-project

# Specify app path every time
tfgrid-compose up ../tfgrid-ai-agent
tfgrid-compose status ../tfgrid-ai-agent
tfgrid-compose ssh ../tfgrid-ai-agent
tfgrid-compose down ../tfgrid-ai-agent
```

### Basic Commands

```bash
# Deploy
tfgrid-compose up [app-path]

# Execute commands on VM
tfgrid-compose exec [app-path] <command>

# AI Agent management (requires context)
tfgrid-compose agent list
tfgrid-compose agent create
tfgrid-compose agent run <project>
tfgrid-compose agent monitor <project>
tfgrid-compose agent stop <project>

# Status & logs
tfgrid-compose status [app-path]
tfgrid-compose ssh [app-path]
tfgrid-compose logs [app-path]

# Destroy
tfgrid-compose down [app-path]
```

### Complete Workflow Example

```bash
# 1. Setup context
echo "app: ../tfgrid-ai-agent" > .tfgrid-compose.yaml

# 2. Deploy
tfgrid-compose up

# 3. Use AI agent
tfgrid-compose agent create
# Follow prompts: name, duration, prompt

# 4. Monitor
tfgrid-compose agent list
tfgrid-compose agent monitor my-project

# 5. Cleanup
tfgrid-compose agent stop my-project
tfgrid-compose down
```

---

## How It Works

**Complete deployment flow:**
1. ✅ **Validates** prerequisites and configuration
2. ✅ **Plans** infrastructure with Terraform
3. ✅ **Provisions** VM on ThreeFold Grid
4. ✅ **Configures** WireGuard networking
5. ✅ **Waits** for SSH to be ready
6. ✅ **Runs** Ansible playbooks
7. ✅ **Deploys** application source code
8. ✅ **Runs** deployment hooks (setup → configure → healthcheck)
9. ✅ **Verifies** deployment success
10. ✅ **Saves** state for management

**Total time:** 2-3 minutes ⚡

## Documentation

### Getting Started
- **[Quick Start Guide](docs/QUICKSTART.md)** - Get started in 5 minutes
- **[AI Agent Guide](docs/AI_AGENT_GUIDE.md)** - Complete AI agent integration guide
- **[Context File Usage](docs/CONTEXT_FILE_USAGE.md)** - Using `.tfgrid-compose.yaml` for simpler commands

### Development
- **[TODO](TODO.md)** - Roadmap and future features
- **[Implementation Summary](IMPLEMENTATION_SUMMARY.md)** - Development notes
- **[Contributing](.github/CONTRIBUTING.md)** - How to contribute

## Patterns

See full pattern documentation above or run:
```bash
tfgrid-compose patterns
```

## Development

### Running Tests

```bash
# Validation tests
./tests/test-validation.sh

# Full lifecycle test
make up APP=../tfgrid-ai-agent
make status APP=../tfgrid-ai-agent
make down APP=../tfgrid-ai-agent
```

### Contributing

Contributions welcome! See [Contributing Guide](.github/CONTRIBUTING.md)

## Troubleshooting

See [Quick Start Guide](docs/QUICKSTART.md#troubleshooting) for common issues.

**Quick fixes:**
- Missing prerequisites: `tfgrid-compose up` will tell you what's missing
- Existing deployment: `make down APP=<app>` then redeploy
- State corruption: `make clean` (⚠️ removes state)

## License

Apache 2.0 - See LICENSE file

---

**Part of:** [TFGrid Studio](https://github.com/tfgrid-studio)  
**Status:** ✅ Complete First Layer  
**Version:** 2.0.0  
**Patterns:** 3/3 Production Ready

**All deployment patterns complete and ready for production!** 🚀

---

## 📖 Complete Documentation Index

| Document | Purpose | Audience |
|----------|---------|----------|
| [README.md](README.md) | Overview and quick reference | Everyone |
| [docs/QUICKSTART.md](docs/QUICKSTART.md) | 5-minute setup guide | New users |
| [docs/AI_AGENT_GUIDE.md](docs/AI_AGENT_GUIDE.md) | AI agent workflows | AI agent users |
| [docs/CONTEXT_FILE_USAGE.md](docs/CONTEXT_FILE_USAGE.md) | Context file guide | All users |
| [TODO.md](TODO.md) | Future roadmap | Contributors |
| [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) | Development notes | Developers |
| [Makefile](Makefile) | Command reference (`make help`) | CLI users |