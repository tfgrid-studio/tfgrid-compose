# Gateway with SSL Example

Production-ready gateway deployment with automatic SSL/TLS, load balancing, and dual network redundancy.

## Overview

This example deploys a complete gateway architecture:
- **1 Gateway VM** - Public IPv4 with nginx reverse proxy
- **2 Backend VMs** - Private networking for your services
- **Automatic SSL** - Let's Encrypt TLS certificates
- **Dual Network** - WireGuard + Mycelium redundancy
- **Load Balancing** - Distribute traffic across backends

## Features

- ✅ Public IPv4 gateway with SSL/TLS
- ✅ Private backend VMs (WireGuard networking)
- ✅ Automatic SSL certificate provisioning
- ✅ Reverse proxy configuration
- ✅ Network redundancy (WireGuard + Mycelium failover)
- ✅ Simple HTML application deployment

## Prerequisites

- ThreeFold mnemonic configured (`~/.config/threefold/mnemonic`)
- Domain name pointing to your gateway (configured after deployment)
- WireGuard installed (`sudo apt install wireguard`)

## Quick Start

### 1. Copy and Customize

```bash
cp -r examples/gateway-ssl my-gateway
cd my-gateway
```

Edit `tfgrid-compose.yaml`:

```yaml
name: my-gateway-app
version: 1.0.0

nodes:
  gateway: 1        # Your gateway node ID
  backend: [8, 13]  # Your backend node IDs

gateway:
  domains:
    - yourdomain.com  # Your domain
  ssl:
    email: your@email.com  # For Let's Encrypt
```

### 2. Deploy

```bash
tfgrid-compose up .
```

### 3. Configure DNS

Point your domain to the gateway IP shown after deployment.

### 4. Access

Visit `https://yourdomain.com` once DNS propagates (5-30 minutes).

## Management

```bash
# Check status
tfgrid-compose status .

# View logs
tfgrid-compose logs .

# SSH to gateway
tfgrid-compose ssh .

# Tear down
tfgrid-compose down .
```

## Customization

### Change Network Mode

```yaml
network:
  mode: wireguard-only  # No Mycelium
  # OR
  mode: both            # Dual network (recommended)
```

### Adjust Resources

```yaml
resources:
  gateway:
    cpu: 4
    memory: 8192  # 8GB
    disk: 100
```

### Deploy Your App

Replace `index.html` with your application and update `deployment/configure.sh`.

## Learn More

- [TFGrid Compose Documentation](../../docs/)
- [Gateway Pattern Reference](../../patterns/gateway/)
