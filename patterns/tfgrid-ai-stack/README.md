# TFGrid AI Stack

AI-powered development platform with integrated Git hosting and deployment.

## Overview

This repository contains the complete TFGrid AI Stack pattern - a multi-VM deployment that provides an AI-powered development environment with integrated Git hosting. The pattern deploys three VMs connected via WireGuard VPN:

- **Gateway VM**: Public API gateway with nginx, monitoring (Prometheus/Grafana), and SSL termination
- **AI Agent VM**: Project creation and management APIs with AI assistance
- **Gitea VM**: Git repository hosting with web interface

## Quick Start

Deploy the complete AI development environment:

```bash
tfgrid-compose up tfgrid-ai-stack
```

## Features

- 🤖 **AI-Powered Development**: Create projects with AI assistance
- 📦 **Integrated Git Hosting**: Built-in Gitea for version control
- 🌐 **Public Deployment**: Automatic web deployment with SSL
- 📊 **Monitoring**: Prometheus + Grafana dashboards
- 🔒 **Secure Networking**: WireGuard VPN for inter-VM communication
- ⚡ **One-Click Deployment**: Single command setup
- 🔄 **Automated Backups**: Scheduled backups with retention policies

## Architecture

```
Internet
    ↓
[Gateway VM] ← nginx, APIs, monitoring
    ↓ (WireGuard VPN)
[AI Agent VM] ← project creation, code generation
    ↓
[Gitea VM] ← Git repositories, web interface
```

## Usage

### Deploy
```bash
tfgrid-compose up tfgrid-ai-stack
```

### Create a Project
```bash
tfgrid-compose exec tfgrid-ai-stack create "portfolio website"
```

### List Projects
```bash
tfgrid-compose exec tfgrid-ai-stack projects
```

### Access Services
```bash
# Get deployment URLs
tfgrid-compose address tfgrid-ai-stack

# SSH into VMs
tfgrid-compose ssh tfgrid-ai-stack
```

### Management Commands
```bash
# Monitor project logs
tfgrid-compose exec tfgrid-ai-stack monitor <project-name>

# Delete a project
tfgrid-compose exec tfgrid-ai-stack delete <project-name>

# Manual backup
tfgrid-compose exec tfgrid-ai-stack backup

# Restore from backup
tfgrid-compose exec tfgrid-ai-stack restore <backup-file>
```

## Configuration

The pattern supports extensive customization through variables:

### Domain & SSL
- `domain`: Custom domain name for public access
- `ssl_email`: Email for SSL certificate (required if domain set)

### Resource Allocation
- `gateway_cpu/memory/disk`: Gateway VM resources
- `ai_agent_cpu/memory/disk`: AI Agent VM resources
- `gitea_cpu/memory/disk`: Gitea VM resources

### Security & Limits
- `api_rate_limit`: API rate limiting
- `max_concurrent_projects`: Concurrent project creation limit

### Backup Settings
- `backup_retention_days`: Backup retention period
- `backup_schedule`: Cron schedule for automated backups

## Requirements

- ThreeFold Grid account with sufficient TFT
- tfgrid-compose CLI installed
- SSH key configured

## Resources

- **CPU**: 8 cores total (default)
- **Memory**: 16GB total (default)
- **Disk**: 200GB total (default)
- **Cost**: ~$15-20/month (varies by node pricing)

## Pattern Structure

```
tfgrid-ai-stack/
├── tfgrid-compose.yaml    # Pattern definition
├── infrastructure/        # Terraform configuration
├── platform/             # Ansible playbooks and roles
├── scripts/              # CLI command scripts
├── ai-agent-api/         # AI Agent API source
├── gateway-api/          # Gateway API source
├── README.md             # This file
└── LICENSE               # Apache 2.0
```

## Development

This pattern is maintained by TFGrid Studio. The reference implementation is also available in the [tfgrid-compose patterns directory](https://github.com/tfgrid-studio/tfgrid-compose/tree/main/patterns/tfgrid-ai-stack).

## Documentation

- [Pattern Documentation](https://docs.tfgrid.studio/patterns/tfgrid-ai-stack)
- [API Reference](https://docs.tfgrid.studio/patterns/tfgrid-ai-stack/api)
- [Troubleshooting](https://docs.tfgrid.studio/patterns/tfgrid-ai-stack/troubleshooting)

## Support

This is an official TFGrid Studio application. For support:
- Documentation: https://docs.tfgrid.studio
- Issues: https://github.com/tfgrid-studio/tfgrid-compose/issues