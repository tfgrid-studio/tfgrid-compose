# Single VM Example

Deploy a simple static website on a single VM.

## Overview

The simplest TFGrid Compose deployment - one VM with nginx serving a static website.

## Features

- ✅ Single VM deployment
- ✅ Public IPv4 access
- ✅ Nginx web server
- ✅ Simple bash deployment hooks
- ✅ Perfect for static sites, landing pages, docs

## Prerequisites

- ThreeFold mnemonic configured (`~/.config/threefold/mnemonic`)

## Quick Start

### 1. Copy and Customize

```bash
cp -r examples/single-vm my-website
cd my-website
```

Edit `tfgrid-compose.yaml`:

```yaml
name: my-website
version: 1.0.0

nodes:
  vm: 1  # Your node ID

resources:
  vm:
    cpu: 2
    memory: 2048  # 2GB
    disk: 25      # 25GB
```

### 2. Customize Your Website

Edit `index.html` with your content or copy your existing HTML files.

### 3. Deploy

```bash
tfgrid-compose up .
```

Deployment takes ~3 minutes. You'll get the VM's public IP.

### 4. Access

Visit `http://<vm-ip>` in your browser.

## Management

```bash
# Check status
tfgrid-compose status .

# SSH to VM
tfgrid-compose ssh .

# Tear down
tfgrid-compose down .
```

## Customization

### Add More Content

Copy your website files:
```bash
cp -r my-site/* .
```

Update `deployment/configure.sh` to copy them:
```bash
cp -r /tmp/app-deployment/* /var/www/html/
```

### Change Resources

```yaml
resources:
  vm:
    cpu: 4
    memory: 4096  # 4GB
    disk: 50      # 50GB
```

## Next Steps

- Add domain and SSL → Use [`gateway-ssl`](../gateway-ssl/) example
- Deploy multiple VMs → Use [`k3s-cluster`](../k3s-cluster/) example
- Add dynamic content → Modify deployment hooks to install your stack

## Learn More

- [TFGrid Compose Documentation](../../docs/)
- [Deployment Hooks Guide](../../docs/HOOKS.md)
