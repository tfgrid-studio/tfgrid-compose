# TFGrid Compose Patterns Guide

**Complete guide to deployment patterns on TFGrid Compose**

---

## Overview

TFGrid Compose supports **3 production-ready deployment patterns** that cover all major use cases:

| Pattern | Use Case | Complexity | Status |
|---------|----------|------------|--------|
| **single-vm** | Development, databases, services | ⭐ Simple | ✅ Production |
| **gateway** | Public web apps, e-commerce | ⭐⭐ Moderate | ✅ Production |
| **k3s** | Cloud-native, microservices | ⭐⭐⭐ Advanced | ✅ Production |

---

## Pattern Selection Guide

### Choose **single-vm** when:

- 🏠 **Development environments:** AI agents, testing, experimentation
- 💾 **Databases:** PostgreSQL, MongoDB, Redis
- ⚙️ **Internal services:** Background workers, cron jobs
- 🔒 **Private applications:** No public access needed

**Example apps:** tfgrid-ai-agent, databases, internal APIs

---

### Choose **gateway** when:

- 🌐 **Public websites:** Need internet access via public IPv4
- 🛒 **E-commerce:** Production storefronts
- 📱 **Web applications:** SaaS products, web portals
- 🔐 **SSL required:** HTTPS with Let's Encrypt

**Example apps:** WordPress, e-commerce sites, customer portals

---

### Choose **k3s** when:

- ☸️ **Microservices:** Multiple interconnected services
- 📦 **Containerized apps:** Docker/OCI containers
- 🔄 **Auto-scaling needed:** Dynamic resource allocation
- 🏢 **Enterprise requirements:** HA, monitoring, GitOps

**Example apps:** Cloud-native SaaS, microservices platforms

---

## Pattern Comparison

### Architecture

| Aspect | single-vm | gateway | k3s |
|--------|-----------|---------|-----|
| **VMs** | 1 | 1 gateway + N backends | 1 mgmt + N control + M workers |
| **Public IP** | Optional | Gateway only | Optional on workers |
| **Networking** | WireGuard/Mycelium | WireGuard/Mycelium | WireGuard/Mycelium |
| **SSL** | Manual | Automatic (Let's Encrypt) | Via Ingress |
| **Load Balancing** | N/A | Nginx/HAProxy | MetalLB + Ingress |

### Resource Requirements

| Pattern | Minimum | Recommended | Typical Production |
|---------|---------|-------------|-------------------|
| **single-vm** | 2 vCPU, 4GB RAM | 4 vCPU, 8GB RAM | 4 vCPU, 8GB RAM |
| **gateway** | 4 vCPU, 6GB RAM | 8 vCPU, 12GB RAM | 16 vCPU, 24GB RAM |
| **k3s** | 12 vCPU, 18GB RAM | 24 vCPU, 48GB RAM | 48+ vCPU, 96+ GB RAM |

### Cost Comparison

Based on typical ThreeFold Grid pricing:

| Pattern | Monthly Cost (Estimated) |
|---------|-------------------------|
| **single-vm** | $10-30 |
| **gateway** | $30-100 |
| **k3s** | $100-500+ |

---

## Pattern Details

### Single-VM Pattern

**Architecture:**
```
[Single VM]
├── Application
├── WireGuard: 10.1.3.2
└── Mycelium: [IPv6]
```

**When to use:**
- Simple, standalone applications
- No public access required
- Cost-sensitive deployments
- Development/testing

**Deployment:**
```bash
tfgrid-compose up myapp  # Uses single-vm by default
```

**Documentation:** [patterns/single-vm/](../patterns/single-vm/)

---

### Gateway Pattern

**Architecture:**
```
Internet → [Gateway VM] → Private Network → [Backend VMs]
           (Public IPv4)                     (WireGuard/Mycelium only)
```

**Two modes:**

**1. NAT Mode** (Simple)
- Direct port forwarding
- Low resource overhead
- Example: `http://185.206.122.150:8081`

**2. Proxy Mode** (Production)
- Nginx + HAProxy
- SSL termination
- Path-based routing
- Example: `https://myapp.com/api`

**When to use:**
- Need public IPv4 access
- Want SSL/HTTPS
- Multiple backend services
- Production web applications

**Deployment:**
```bash
# Specify in manifest
pattern: gateway

# Or via command line
tfgrid-compose up myapp --pattern gateway
```

**Documentation:** [patterns/gateway/README.md](../patterns/gateway/README.md)

---

### K3s Pattern

**Architecture:**
```
[Management Node] → [Control Plane] → [Worker Nodes]
     kubectl              K3s API         Application Pods
     helm                etcd            Container Runtime
     k9s                                 Storage
```

**Components:**
- **Management Node:** kubectl, helm, k9s, Ansible
- **Control Plane:** K3s server, etcd, API server
- **Workers:** K3s agents, container runtime, pods
- **Add-ons:** MetalLB, Nginx Ingress, storage

**When to use:**
- Microservices architecture
- Need container orchestration
- Auto-scaling required
- Enterprise HA requirements

**Deployment:**
```bash
# Specify in manifest
pattern: k3s

# Or via command line
tfgrid-compose up myapp --pattern k3s
```

**Documentation:** [patterns/k3s/README.md](../patterns/k3s/README.md)

---

## Pattern Migration

### From single-vm to gateway

**Why migrate:**
- Need public access
- Want SSL/HTTPS
- Need load balancing

**Steps:**
1. Update `tfgrid-compose.yaml`:
   ```yaml
   pattern: gateway  # Change from single-vm
   ```
2. Add gateway configuration to infrastructure
3. Redeploy: `tfgrid-compose up`

**Migration time:** ~30 minutes

---

### From gateway to k3s

**Why migrate:**
- Need microservices
- Want container orchestration
- Need auto-scaling

**Steps:**
1. Containerize application (create Dockerfile)
2. Create Kubernetes manifests (`kubernetes/*.yaml`)
3. Update `tfgrid-compose.yaml`:
   ```yaml
   pattern: k3s
   kubernetes:
     manifests:
       - kubernetes/deployment.yaml
       - kubernetes/service.yaml
   ```
4. Redeploy: `tfgrid-compose up`

**Migration time:** 2-4 hours (including containerization)

---

## App Manifest Configuration

### Single-VM

```yaml
name: myapp
version: 1.0.0

pattern: single-vm

resources:
  cpu: 4
  memory: 8192
  disk: 100

deployment:
  hooks:
    - deployment/setup.sh
    - deployment/configure.sh
    - deployment/healthcheck.sh
```

### Gateway

```yaml
name: myapp
version: 1.0.0

pattern: gateway

resources:
  gateway:
    cpu: 2
    memory: 4096
  backend:
    cpu: 4
    memory: 8192
    count: 2

gateway:
  type: proxy        # or 'nat'
  domain: myapp.com
  ssl: true
```

### K3s

```yaml
name: myapp
version: 1.0.0

pattern: k3s

resources:
  control:
    cpu: 4
    memory: 8192
    count: 3
  worker:
    cpu: 8
    memory: 16384
    count: 3

kubernetes:
  manifests:
    - kubernetes/*.yaml
  helm_charts:
    - name: postgresql
      repo: https://charts.bitnami.com/bitnami
```

---

## Common Commands

All patterns support these commands:

```bash
# Deploy
tfgrid-compose up [app]

# Management
tfgrid-compose status [app]
tfgrid-compose logs [app]
tfgrid-compose ssh [app]
tfgrid-compose address [app]

# Cleanup
tfgrid-compose down [app]
```

### Pattern-specific commands

**Gateway:**
```bash
tfgrid-compose ssl-setup [app]  # Set up SSL
tfgrid-compose ssl-renew [app]  # Renew SSL
tfgrid-compose reload [app]     # Reload Nginx
```

**K3s:**
```bash
tfgrid-compose kubectl get nodes    # Run kubectl
tfgrid-compose k9s                  # Launch k9s TUI
tfgrid-compose scale workers --count 5
```

---

## Best Practices

### Pattern Selection

1. **Start simple:** Begin with single-vm, migrate when needed
2. **Cost awareness:** Gateway and K3s cost more - use when necessary
3. **Over-provision initially:** Better to have spare resources
4. **Test locally first:** Use small configs for testing

### Resource Planning

**Single-VM:**
- Production: 4+ vCPU, 8+ GB RAM
- Development: 2 vCPU, 4GB RAM

**Gateway:**
- Gateway: 2-4 vCPU, 4-8GB RAM
- Backends: 4+ vCPU, 8+ GB RAM each
- Rule: Gateway should handle 2x backend count comfortably

**K3s:**
- Control: 4-8 vCPU, 8-16GB RAM per node
- Workers: 8+ vCPU, 16+ GB RAM per node
- Management: 1-2 vCPU, 2-4GB RAM

### Security

**All patterns:**
- ✅ Use SSH keys (never passwords)
- ✅ Keep systems updated
- ✅ Monitor logs regularly

**Gateway:**
- ✅ Enable SSL for production
- ✅ Use proxy mode for better security
- ✅ Keep backends private (no public IP)

**K3s:**
- ✅ Enable RBAC
- ✅ Use network policies
- ✅ Regular Kubernetes updates

---

## Troubleshooting

### Pattern doesn't deploy

```bash
# Check pattern exists
ls patterns/

# Verify configuration
cat infrastructure/credentials.auto.tfvars

# Check logs
tfgrid-compose logs
```

### Wrong pattern deployed

```bash
# Clean up
tfgrid-compose down

# Update manifest
nano tfgrid-compose.yaml
# Change pattern: field

# Redeploy
tfgrid-compose up
```

### Pattern switching

```bash
# Patterns use different infrastructure
# Must destroy old deployment first
tfgrid-compose down

# Update pattern
# Edit tfgrid-compose.yaml

# Deploy new pattern
tfgrid-compose up
```

---

## Examples

### Development → Production Migration

**Phase 1: Development (single-vm)**
```yaml
pattern: single-vm
resources:
  cpu: 2
  memory: 4096
```

**Phase 2: Beta (gateway with 1 backend)**
```yaml
pattern: gateway
resources:
  backend:
    count: 1
gateway:
  ssl: true
  domain: beta.myapp.com
```

**Phase 3: Production (gateway with multiple backends)**
```yaml
pattern: gateway
resources:
  backend:
    count: 3
gateway:
  type: proxy
  ssl: true
  domain: myapp.com
```

**Phase 4: Scale (k3s)**
```yaml
pattern: k3s
resources:
  control:
    count: 3
  worker:
    count: 5
```

---

## Additional Resources

- **Pattern Contract:** [PATTERN_CONTRACT.md](../patterns/PATTERN_CONTRACT.md)
- **Single-VM Docs:** [patterns/single-vm/](../patterns/single-vm/)
- **Gateway Docs:** [patterns/gateway/README.md](../patterns/gateway/README.md)
- **K3s Docs:** [patterns/k3s/README.md](../patterns/k3s/README.md)
- **External Sources:**
  - Gateway: [external-repos/tfgrid-gateway/](../../external-repos/tfgrid-gateway/)
  - K3s: [external-repos/tfgrid-k3s/](../../external-repos/tfgrid-k3s/)

---

**All 3 patterns are production-ready and battle-tested!** 🎉

Choose the right pattern for your needs and deploy with confidence.

---

**Last Updated:** 2025-10-09  
**Version:** 2.0.0 (Complete First Layer)
