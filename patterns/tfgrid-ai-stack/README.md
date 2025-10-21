# TFGrid AI Stack Pattern

**Version:** 0.12.0-dev  
**Status:** Development  
**Type:** Multi-VM Pattern

## Overview

The TFGrid AI Stack pattern enables AI-powered code generation with integrated Git hosting and automatic deployment. With a single command, you can deploy a complete development environment and create projects that are instantly live.

## Features

- 🤖 **AI Code Generation** - Generate projects with natural language descriptions
- 📦 **Integrated Git** - Self-hosted Gitea for repository management
- 🚀 **Auto-Deployment** - Generated code automatically deployed and live
- 🔒 **Private/Public Modes** - Deploy privately or expose to internet
- 📊 **Full Observability** - Prometheus, Grafana, and Loki monitoring
- 💾 **Automated Backups** - Daily backups with disaster recovery
- 🔐 **Security Hardened** - Firewalls, rate limiting, intrusion detection

## Quick Start

### Deploy the Stack

```bash
# Private mode (default - no external access)
tfgrid-compose up tfgrid-ai-stack

# Public mode (with domain and SSL)
tfgrid-compose up tfgrid-ai-stack --domain example.com --ssl-email admin@example.com
```

### Create Projects

```bash
# Generate and deploy a project
tfgrid-compose create "portfolio website with dark mode"

# Output:
# 🤖 Generating code with AI...
# 📁 Creating Git repository...
# 🚀 Deploying to gateway...
# ✅ Project created successfully!
# 📁 Repository: https://example.com/gitea/repos/portfolio
# 🌐 Live site: https://example.com/portfolio
# ⏱️  Duration: 3m 24s
```

### Manage Projects

```bash
# List all projects
tfgrid-compose projects

# Monitor project logs
tfgrid-compose monitor <project-name>

# Delete a project
tfgrid-compose delete <project-name>
```

## Architecture

```
┌─────────────────────────────────────┐
│          Internet (Optional)        │
└────────────┬────────────────────────┘
             │
        ┌────▼─────┐
        │ Gateway  │  2 CPU, 4GB RAM
        │   VM     │  - Nginx + SSL
        │          │  - Route API
        │          │  - Prometheus
        │          │  - Grafana
        └──┬───┬───┘
           │   │
  WireGuard│   │Mycelium
           │   │
    ───────┼───┼───────
           │   │
   ┌───────▼───▼───────┐
   │                   │
┌──▼──────┐    ┌───────▼──┐
│ AI Agent│    │  Gitea   │
│   VM    │    │    VM    │
│ 4CPU 8GB│    │ 2CPU 4GB │
└─────────┘    └──────────┘
```

## Components

### Gateway VM (2 CPU, 4GB RAM, 50GB disk)
- **Nginx**: Reverse proxy and static file serving
- **Route API**: Dynamic route management
- **Prometheus**: Metrics collection
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation

### AI Agent VM (4 CPU, 8GB RAM, 100GB disk)
- **qwen-cli**: AI code generation
- **Project API**: Workflow orchestration
- **Project DB**: Metadata tracking

### Gitea VM (2 CPU, 4GB RAM, 50GB disk)
- **Gitea**: Git server with web UI
- **PostgreSQL**: Repository database
- **Backups**: Automated daily backups

## Configuration

### Pattern Variables

Edit `tfgrid-compose.yaml` or pass as flags:

```yaml
variables:
  # Domain configuration (optional for public mode)
  domain: "example.com"
  ssl_email: "admin@example.com"
  
  # Resource allocation
  gateway_cpu: 2
  gateway_memory: 4096
  ai_agent_cpu: 4
  ai_agent_memory: 8192
  gitea_cpu: 2
  gitea_memory: 4096
  
  # Network configuration
  wireguard_port: 51820
  private_network: "10.1.1.0/24"
  
  # Security
  api_rate_limit: "100r/m"
  max_concurrent_projects: 10
  
  # Backup configuration
  backup_retention_days: 30
  backup_schedule: "0 2 * * *"  # 2 AM daily
```

### Deployment Modes

**Private Mode (Default):**
- No external access
- All services on WireGuard private network
- Access via SSH tunnel or VPN

**Public Mode (with --domain):**
- Gateway exposed to internet
- SSL/TLS with Let's Encrypt
- Gitea proxied through gateway
- Rate limiting and DDoS protection

## Monitoring

### Access Dashboards

```bash
# Port forward Grafana
ssh -L 3000:localhost:3000 root@gateway-ip

# Open in browser
http://localhost:3000

# Default credentials (change on first login)
Username: admin
Password: admin
```

### Available Dashboards
1. **System Overview** - VM health, resources, uptime
2. **API Performance** - Request rates, latency, errors
3. **Project Metrics** - Creation rate, active projects, failures
4. **Operational** - Backups, alerts, incident timeline

### Key Metrics

```promql
# System uptime
up{job="health-checks"}

# API response time (p95)
histogram_quantile(0.95, 
  rate(http_request_duration_seconds_bucket[5m])
)

# Project creation success rate
sum(rate(project_creation_success_total[5m])) /
sum(rate(project_creation_attempts_total[5m]))

# Active projects count
count(project_status{status="active"})
```

## Backup & Recovery

### Automated Backups

Backups run daily at 2 AM:
- Gitea database (PostgreSQL dump)
- Project metadata
- Nginx configurations

Location: `/var/backups/` on each VM

### Manual Backup

```bash
# SSH to Gitea VM
ssh root@gitea-ip

# Run backup
/opt/tfgrid-ai-stack/scripts/backup-gitea.sh

# Backup stored in /var/backups/gitea/
```

### Disaster Recovery

```bash
# List available backups
ssh root@gitea-ip "ls -lh /var/backups/gitea/"

# Restore from backup
ssh root@gitea-ip "/opt/tfgrid-ai-stack/scripts/restore-gitea.sh /var/backups/gitea/gitea_backup_YYYYMMDD_HHMMSS.tar.gz"

# Verify restoration
tfgrid-compose projects  # Should list all projects
```

**Recovery Time Objective (RTO):** <1 hour  
**Recovery Point Objective (RPO):** <24 hours

## Security

### Network Security
- WireGuard VPN between VMs
- Firewall (UFW) on all VMs
- fail2ban for intrusion detection
- Rate limiting on all APIs

### Access Control
- SSH key-only authentication
- API token authentication
- Token rotation support
- No default passwords

### Data Security
- TLS/SSL for all external traffic
- Encrypted WireGuard tunnel
- Encrypted backups (optional)
- Secure secret storage

### Security Hardening
```bash
# Check security status
ssh root@gateway-ip "/opt/tfgrid-ai-stack/scripts/security-check.sh"

# Rotate API tokens
ssh root@gateway-ip "/opt/tfgrid-ai-stack/scripts/rotate-tokens.sh"
```

## Troubleshooting

### Common Issues

**Deployment fails:**
```bash
# Check Terraform logs
cat deployment.log

# Verify ThreeFold Grid capacity
tfgrid-compose farms --available

# Retry with different farm
tfgrid-compose up tfgrid-ai-stack --farm alternative-farm
```

**Project creation fails:**
```bash
# Check AI Agent logs
ssh root@ai-agent-ip "journalctl -u ai-agent -n 100"

# Check Gitea connectivity
ssh root@ai-agent-ip "curl http://gitea:3000/api/v1/version"

# Check Gateway API
ssh root@ai-agent-ip "curl http://gateway:3000/api/v1/health"
```

**Service not responding:**
```bash
# Check service status
ssh root@<vm-ip> "systemctl status <service>"

# Restart service
ssh root@<vm-ip> "systemctl restart <service>"

# View logs
ssh root@<vm-ip> "journalctl -u <service> -f"
```

### Health Check

```bash
# Run comprehensive health check
ssh root@gateway-ip "/opt/tfgrid-ai-stack/scripts/health-check.sh"

# Expected output:
# ✅ 1. VM Status: All VMs online
# ✅ 2. Service Status: All services healthy
# ✅ 3. Metrics Collection: 10+ targets
# ✅ 4. Backup Status: Recent backup exists
# ✅ 5. Disk Space: All VMs <80%
# ✅ 6. API Response Time: <500ms
# ✅ 7. Project Creation Test: <5 minutes
```

## Performance

### Service Level Objectives (SLOs)

| Metric | Target | Current |
|--------|--------|---------|
| Deployment time | <10 min (p95) | TBD |
| Project creation | <5 min (p95) | TBD |
| API response | <500ms (p95) | TBD |
| System uptime | ≥99.5% | TBD |

### Capacity

- **Concurrent projects:** 10+ supported
- **Total projects:** 100+ per deployment
- **API throughput:** 100 requests/minute
- **Storage:** Scales with disk size

## Upgrading

```bash
# Pull latest version
git pull origin main

# Backup current state
tfgrid-compose backup tfgrid-ai-stack

# Update pattern
tfgrid-compose up tfgrid-ai-stack --upgrade

# Verify health
tfgrid-compose health tfgrid-ai-stack
```

## API Reference

### Gateway Route Management API

**Base URL:** `http://gateway:3000/api/v1`

**Authentication:** Bearer token in `Authorization` header

**Endpoints:**
- `POST /routes` - Create route
- `GET /routes` - List routes
- `DELETE /routes/{id}` - Delete route
- `GET /health` - Health check

**Example:**
```bash
curl -X POST http://gateway:3000/api/v1/routes \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "path": "/my-project",
    "backend": "http://gateway/var/www/my-project",
    "ssl": true
  }'
```

### AI Agent Project API

**Base URL:** `http://ai-agent:8080/api/v1`

**Authentication:** Internal only (WireGuard network)

**Endpoints:**
- `POST /projects` - Create project
- `GET /projects` - List projects
- `DELETE /projects/{id}` - Delete project

## Development

### Local Testing

```bash
# Deploy test stack
tfgrid-compose up tfgrid-ai-stack --test

# Run integration tests
cd tfgrid-compose/patterns/tfgrid-ai-stack
./scripts/test.sh

# Load testing
cd tests/load
k6 run project-creation-load.js
```

### Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md) for development guidelines.

## Support

- **Documentation:** https://docs.tfgrid.studio
- **Issues:** https://github.com/tfgrid-studio/tfgrid-compose/issues
- **Community:** https://forum.threefold.io

## License

Apache License 2.0 - See [LICENSE](../../LICENSE)

---

**Pattern Version:** 0.12.0-dev  
**Last Updated:** October 21, 2025  
**Maintainer:** TFGrid Studio Team