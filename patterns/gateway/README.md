# Gateway Pattern - Public IPv4 Web Hosting

**Status:** ✅ Production Ready  
**Version:** 1.0.0  
**Use Cases:** Production web apps, e-commerce, public-facing services

---

## Overview

The Gateway pattern deploys a **multi-VM architecture** with:
- **1 Gateway VM** with public IPv4 address (acts as reverse proxy)
- **N Backend VMs** with private networking (WireGuard/Mycelium only)
- **Automatic SSL** via Let's Encrypt
- **Load balancing** and health checking
- **Two modes:** NAT-based or Proxy-based (HAProxy + Nginx)

---

## Architecture

```
Internet
   ↓
[Gateway VM] (Public IPv4: 185.206.122.150)
   ├── Nginx/HAProxy (reverse proxy + SSL termination)
   ├── WireGuard: 10.1.3.2
   └── Mycelium: [IPv6]
   ↓
Private Network (WireGuard/Mycelium)
   ↓
[Backend VMs] (No public IP)
   ├── Backend 1 - WireGuard: 10.1.4.2
   ├── Backend 2 - WireGuard: 10.1.5.2
   └── Backend N - WireGuard: 10.1.N.2
```

---

## Quick Start

### 1. Configure

```bash
cd tfgrid-compose/patterns/gateway/infrastructure
cp credentials.auto.tfvars.example credentials.auto.tfvars
nano credentials.auto.tfvars
```

**Minimum configuration:**
```hcl
tfgrid_network = "main"
gateway_node = 1000        # Node with public IPv4
internal_nodes = [2000]    # Backend nodes (IPv6 only)
```

### 2. Deploy

```bash
# From your app directory with tfgrid-compose.yaml
tfgrid-compose up --pattern gateway

# Or specify pattern in manifest:
# pattern: gateway
tfgrid-compose up
```

### 3. Configure SSL (Optional but Recommended)

```bash
# Point your domain to the gateway IP
# Then enable SSL
export DOMAIN_NAME=myapp.com
export ENABLE_SSL=true
tfgrid-compose ssl-setup
```

---

## Gateway Modes

### NAT Mode (Default)

**Best for:** Simple deployments, port-based access

- Direct port forwarding (e.g., `:8081`, `:8082`)
- Minimal resource overhead
- Fast and simple

**Example:**
```bash
export GATEWAY_TYPE=gateway_nat
tfgrid-compose up
# Access: http://185.206.122.150:8081
```

### Proxy Mode (Production)

**Best for:** Production apps, SSL, path-based routing

- HAProxy for load balancing
- Nginx for advanced routing
- SSL/TLS termination
- Path-based access (e.g., `/app1`, `/app2`)

**Example:**
```bash
export GATEWAY_TYPE=gateway_proxy
tfgrid-compose up
# Access: https://myapp.com/backend1
```

---

## Features

### ✅ Public IPv4 Access
- Gateway gets dedicated public IPv4
- Backends remain private (secure)

### ✅ SSL/TLS Support
- Free Let's Encrypt certificates
- Automatic renewal
- HTTP to HTTPS redirect
- SSL termination at gateway

### ✅ Load Balancing
- Distribute traffic across backends
- Health checks
- Automatic failover

### ✅ Network Redundancy
- WireGuard + Mycelium dual networking
- Automatic failover if one network fails

---

## Configuration Options

### Infrastructure Variables

```hcl
# Gateway VM specs
gateway_cpu = 2
gateway_mem = 4096   # 4GB RAM
gateway_disk = 50    # 50GB storage

# Backend VM specs
internal_cpu = 2
internal_mem = 2048  # 2GB RAM
internal_disk = 25   # 25GB storage
```

### Environment Variables

```bash
# Gateway type
export GATEWAY_TYPE=gateway_nat    # or gateway_proxy

# SSL configuration
export DOMAIN_NAME=myapp.com
export ENABLE_SSL=true
export SSL_EMAIL=admin@myapp.com

# Network configuration
export MAIN_NETWORK=wireguard      # or mycelium
export NETWORK_MODE=both           # wireguard-only, mycelium-only, both
```

---

## Available Commands

```bash
# Deploy
tfgrid-compose up --pattern gateway

# Manage
tfgrid-compose status
tfgrid-compose logs
tfgrid-compose ssh          # Connect to gateway
tfgrid-compose address      # Show all IPs

# SSL management
tfgrid-compose ssl-setup    # Initial SSL setup
tfgrid-compose ssl-renew    # Renew certificates

# Reload config
tfgrid-compose reload       # Reload Nginx config

# Cleanup
tfgrid-compose down
```

---

## Application Requirements

Your app must provide these deployment hooks in `deployment/`:

### Required Hooks

**`deployment/setup.sh`** - Install dependencies on backend VMs
```bash
#!/usr/bin/env bash
apt-get update
apt-get install -y nginx nodejs npm
npm install
```

**`deployment/configure.sh`** - Configure your application
```bash
#!/usr/bin/env bash
cd /opt/app
npm run build
systemctl restart myapp
```

**`deployment/healthcheck.sh`** - Verify deployment
```bash
#!/usr/bin/env bash
curl -f http://localhost:8080/health || exit 1
```

---

## App Manifest

In your app's `tfgrid-compose.yaml`:

```yaml
name: my-web-app
version: 1.0.0

pattern:
  recommended: gateway
  
resources:
  gateway:
    cpu: 2
    memory: 4096
    disk: 50
  backend:
    cpu: 4
    memory: 8192
    disk: 100
    count: 2

gateway:
  domain: myapp.com
  ssl: true
  proxy_config: custom-nginx.conf  # Optional
```

---

## Examples

### Simple Web App

```yaml
name: simple-website
pattern: gateway

resources:
  backend:
    count: 1

deployment:
  hooks:
    - deployment/setup.sh
    - deployment/configure.sh
    - deployment/healthcheck.sh
```

### Load-Balanced API

```yaml
name: api-service
pattern: gateway

resources:
  backend:
    count: 3    # 3 backend servers

gateway:
  type: proxy
  ssl: true
  domain: api.mycompany.com
```

### E-Commerce Site

```yaml
name: shop
pattern: gateway

resources:
  gateway:
    cpu: 2
    memory: 4096
  backend:
    cpu: 8
    memory: 16384
    disk: 200
    count: 2

gateway:
  type: proxy
  ssl: true
  domain: shop.example.com
  load_balancing: round_robin
```

---

## Troubleshooting

### Gateway not accessible

```bash
# Check gateway status
tfgrid-compose status

# Check logs
tfgrid-compose logs

# Verify IP
tfgrid-compose address
```

### SSL issues

```bash
# Check certificate
tfgrid-compose ssh
certbot certificates

# Renew manually
certbot renew --force-renewal
```

### Backend connectivity

```bash
# Test from gateway
tfgrid-compose ssh
ping 10.1.4.2  # Backend WireGuard IP
```

---

## Performance & Scaling

### Resource Guidelines

| Backend Count | Gateway RAM | Use Case |
|---------------|-------------|----------|
| 1-2 | 4GB | Small apps |
| 3-5 | 8GB | Medium apps |
| 6-10 | 16GB | Large apps |

### Scaling

```bash
# Add more backends by updating infrastructure config
nano infrastructure/credentials.auto.tfvars
# Add more node IDs to internal_nodes

# Redeploy
tfgrid-compose up
```

---

## Security

### Best Practices

- ✅ Keep backends private (no public IP)
- ✅ Enable SSL for production
- ✅ Use strong SSH keys
- ✅ Regular security updates
- ✅ Monitor logs for suspicious activity

### Firewall

Gateway automatically configures:
- Port 80/443 open (HTTP/HTTPS)
- Port 22 open (SSH)
- All other ports blocked
- Backend ports only accessible via private network

---

## Links

- [Pattern Contract](../PATTERN_CONTRACT.md)
- [External Source](../../external-repos/tfgrid-gateway/)
- [TFGrid Compose Docs](../../docs/)

---

**Last Updated:** 2025-10-09  
**Status:** ✅ Production Ready  
**Pattern Type:** Multi-VM with Public IPv4
