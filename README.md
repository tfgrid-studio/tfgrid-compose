# TFGrid Deployer

**Universal deployment orchestrator for ThreeFold Grid applications.**

[![Status](https://img.shields.io/badge/status-production--ready-green)]() 
[![Version](https://img.shields.io/badge/version-0.1.0--mvp-blue)]() 
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)]()

## Overview

TFGrid Deployer is a production-ready deployment platform that makes deploying applications on ThreeFold Grid as simple as `tfgrid-compose up`.

**Key Features:**
- ✅ **One-command deployment** - From zero to running app in 2-3 minutes
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

**🎉 PRODUCTION READY - v0.1.0-mvp**

### Completed ✅
- [x] Full deployment orchestration (Terraform + WireGuard + Ansible)
- [x] Input validation and error handling
- [x] Idempotency protection
- [x] Remote command execution (`exec`)
- [x] Quick start documentation
- [x] Installation script
- [x] Help system with examples
- [x] Single-VM pattern (fully tested)

### In Development 🚧
- [ ] Gateway pattern (scaffolded)
- [ ] K3s pattern (scaffolded)
- [ ] Automated test suite
- [ ] Video tutorials

## Patterns

### single-vm 

Single VM deployment with Wireguard and Mycelium networking.

**Use cases:**
- Development environments
- Databases (PostgreSQL, MongoDB, Redis)
- Internal services
- AI agents
- Background workers

---

### gateway 

Gateway VM with public IPv4 + backend VMs with private networking.

**Use cases:**
- Production web applications
- E-commerce sites
- Multi-tier applications
- Traditional hosting with public access

**Features:**
- Public IPv4 on gateway
- Nginx reverse proxy
- SSL/TLS termination
- Load balancing
- Private backend network

---

### k3s 

Kubernetes cluster (K3s) with master and worker nodes.

**Use cases:**
- Cloud-native applications
- Microservices architectures
- Production SaaS platforms
- High availability requirements

**Features:**
- Lightweight Kubernetes (K3s)
- Traefik ingress controller
- Local-path storage provisioner
- kubectl access
- Auto-scaling workers

**Commands supported:**
- `logs` - Show application logs
- `status` - Check application status
- `address` - Show IP addresses

## Quick Start

### 1. Install

```bash
# Clone the repository
git clone https://github.com/tfgrid-compose/tfgrid-deployer
cd tfgrid-deployer

# Run installer (adds to PATH)
./install.sh
```

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
```

### 3. Deploy

```bash
# Deploy an application
tfgrid-compose up ../tfgrid-ai-agent
```

That's it! Your app is deployed and running. 🎉

## Usage

### Basic Commands

```bash
# Deploy an application
tfgrid-compose up <app-path>

# Execute commands on deployed VM
tfgrid-compose exec <app-path> <command>

# Check deployment status
tfgrid-compose status <app-path>

# SSH into VM
tfgrid-compose ssh <app-path>

# View logs
tfgrid-compose logs <app-path>

# Destroy deployment
tfgrid-compose down <app-path>
```

### Complete Workflow Example

```bash
# 1. Deploy the AI agent
tfgrid-compose up ../tfgrid-ai-agent

# 2. Use it (from your local machine!)
tfgrid-compose exec ../tfgrid-ai-agent login
tfgrid-compose exec ../tfgrid-ai-agent create my-webapp
tfgrid-compose exec ../tfgrid-ai-agent run my-webapp

# 3. Check what's happening
tfgrid-compose status ../tfgrid-ai-agent
tfgrid-compose exec ../tfgrid-ai-agent logs my-webapp

# 4. SSH if needed
tfgrid-compose ssh ../tfgrid-ai-agent

# 5. Destroy when done
tfgrid-compose down ../tfgrid-ai-agent
```

### Using Make (Convenience)

```bash
# Set app once
export APP=../tfgrid-ai-agent

# Then use short commands
make up
make status
make ssh
make down
```

### What Happens During Deployment

1. ✅ **Validates** prerequisites (Terraform, Ansible, mnemonic)
2. ✅ **Checks** app manifest and structure
3. ✅ **Prevents** duplicate deployments
4. ✅ **Creates** VM infrastructure (Terraform)
5. ✅ **Configures** WireGuard networking
6. ✅ **Waits** for SSH readiness
7. ✅ **Configures** platform (Ansible - 15+ tasks)
8. ✅ **Deploys** application source code
9. ✅ **Runs** deployment hooks (setup → configure → healthcheck)
10. ✅ **Verifies** deployment success
11. ✅ **Saves** state for management

**Total time:** 2-3 minutes ⚡

## Documentation

### Getting Started
- **[Quick Start Guide](docs/QUICKSTART.md)** - Get started in 5 minutes
- **[AI Agent Guide](docs/AI_AGENT_GUIDE.md)** - Complete AI agent integration guide

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

**Part of:** [TFGrid Compose](https://github.com/tfgrid-compose)  
**Status:** ✅ Production Ready (MVP)  
**Version:** 0.1.0-mvp

**Ready for beta testing!** 🚀

---

## 📖 Complete Documentation Index

| Document | Purpose | Audience |
|----------|---------|----------|
| [README.md](README.md) | Overview and quick reference | Everyone |
| [SUCCESS.md](SUCCESS.md) | Achievement summary | Stakeholders |
| [docs/QUICKSTART.md](docs/QUICKSTART.md) | 5-minute setup guide | New users |
| [docs/AI_AGENT_GUIDE.md](docs/AI_AGENT_GUIDE.md) | AI agent workflows | AI agent users |
| [TODO.md](TODO.md) | Future roadmap | Contributors |
| [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) | Development notes | Developers |
| [Makefile](Makefile) | Command reference (`make help`) | CLI users |