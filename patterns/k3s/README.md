# K3s Pattern - Kubernetes Cluster

**Status:** ✅ Production Ready  
**Version:** 1.0.0  
**Use Cases:** Cloud-native apps, microservices, production SaaS

---

## Overview

The K3s pattern deploys a **complete Kubernetes cluster** with:
- **N Control Plane Nodes** (K3s masters)
- **M Worker Nodes** (K3s agents)
- **P Ingress Nodes** (optional, dedicated with public IPs + Keepalived)
- **1 Management Node** (kubectl, helm, k9s pre-installed)
- **MetalLB** load balancer
- **Nginx Ingress Controller**
- **Private networking** (WireGuard/Mycelium)

---

## Architecture

### Standard Architecture (without dedicated ingress)

```
[Management Node] (10.1.2.2)
   ├── kubectl, helm, k9s
   ├── Ansible for cluster management
   └── WireGuard + Mycelium
   ↓
K3s Cluster (WireGuard: 10.1.x.x)
   ↓
[Control Plane Nodes] (Masters)
   ├── Control 1 - 10.1.3.2
   ├── Control 2 - 10.1.4.2
   └── Control 3 - 10.1.5.2
   ↓
[Worker Nodes] (Agents)
   ├── Worker 1 - 10.1.6.2
   ├── Worker 2 - 10.1.7.2
   └── Worker 3 - 10.1.8.2
```

### Full HA Architecture (with dedicated ingress nodes)

```
                    ┌─────────────┐
                    │   Internet  │
                    └──────┬──────┘
                           │
              DNS A records (2 IPs)
                           │
           ┌───────────────┴───────────────┐
           ▼                               ▼
    ┌─────────────┐                 ┌─────────────┐
    │  Ingress 1  │◄───VRRP/VIP───►│  Ingress 2  │
    │  (public)   │   Keepalived   │  (public)   │
    │  Nginx+K3s  │                │  Nginx+K3s  │
    └──────┬──────┘                └──────┬──────┘
           │       WireGuard mesh         │
           └───────────────┬──────────────┘
                           │
    ┌──────────────────────┼──────────────────────┐
    │                      │                      │
    ▼                      ▼                      ▼
┌────────┐           ┌────────┐           ┌────────┐
│Worker 1│           │Worker 2│           │Worker 3│
│(private)│          │(private)│          │(private)│
│App Pods│           │App Pods│           │App Pods│
└────────┘           └────────┘           └────────┘
    │                      │                      │
    └──────────────────────┼──────────────────────┘
                           │
    ┌──────────────────────┼──────────────────────┐
    │                      │                      │
    ▼                      ▼                      ▼
┌────────┐           ┌────────┐           ┌────────┐
│Master 1│◄─────────►│Master 2│◄─────────►│Master 3│
│  etcd  │   etcd    │  etcd  │   cluster │  etcd  │
│(private)│          │(private)│          │(private)│
└────────┘           └────────┘           └────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │ Management  │
                    │   Node      │
                    │kubectl/helm │
                    └─────────────┘
```

**Benefits of dedicated ingress nodes:**
- **Isolation**: Ingress traffic doesn't compete with application pods
- **Security**: Only ingress nodes have public IPs
- **HA Failover**: Keepalived provides automatic failover (~3s)
- **Scalability**: Scale ingress independently from workers

---

## Quick Start

### 1. Configure

```bash
cd tfgrid-compose/patterns/k3s/infrastructure
cp credentials.auto.tfvars.example credentials.auto.tfvars
nano credentials.auto.tfvars
```

**Minimum configuration:**
```hcl
tfgrid_network = "main"
management_node = 1000      # Management node
control_nodes = [2000]      # Control plane (1 or more)
worker_nodes = [3000, 3001] # Workers (1 or more)

# Node specifications
control_cpu = 4
control_mem = 8192   # 8GB RAM
worker_cpu = 8
worker_mem = 16384   # 16GB RAM
```

**Full HA configuration (with dedicated ingress):**
```hcl
tfgrid_network = "main"
management_node = 1000
control_nodes = [2000, 2001, 2002]  # 3 masters for HA etcd
worker_nodes = [3000, 3001, 3002]   # 3 workers for app pods
ingress_nodes = [4000, 4001]        # 2 dedicated ingress nodes

# Node specifications
control_cpu = 4
control_mem = 8192    # 8GB RAM
worker_cpu = 8
worker_mem = 16384    # 16GB RAM
ingress_cpu = 2
ingress_mem = 4096    # 4GB RAM

# Workers don't need public IPs when using dedicated ingress
worker_public_ipv4 = false
```

### 2. Deploy

```bash
# From your app directory with tfgrid-compose.yaml
tfgrid-compose up --pattern k3s

# Or specify pattern in manifest:
# pattern: k3s
tfgrid-compose up
```

### 3. Access Cluster

```bash
# Connect to management node
tfgrid-compose ssh

# Use kubectl
kubectl get nodes
kubectl get pods -A

# Use k9s (interactive TUI)
k9s
```

---

## Features

### ✅ Lightweight Kubernetes
- K3s instead of full Kubernetes
- ~100MB binary vs. multi-GB
- Fast deployment (minutes, not hours)

### ✅ High Availability
- Multiple control plane nodes
- Automatic leader election
- Worker node redundancy

### ✅ Production Components
- **MetalLB:** Load balancer for services
- **Nginx Ingress:** External traffic routing
- **Flannel:** Pod networking (VXLAN)
- **Local-path storage:** Persistent volumes

### ✅ Management Tools
- **kubectl:** Kubernetes CLI
- **helm:** Package manager
- **k9s:** Terminal UI
- **Ansible:** Cluster automation

---

## Configuration Options

### Infrastructure Variables

```hcl
# Management node
management_cpu = 1
management_mem = 2048  # 2GB RAM
management_disk = 25   # 25GB storage

# Control plane nodes
control_cpu = 4
control_mem = 8192     # 8GB RAM
control_disk = 100     # 100GB storage

# Worker nodes
worker_cpu = 8
worker_mem = 16384     # 16GB RAM
worker_disk = 250      # 250GB storage

# Optional: Public IPv4 for workers
worker_public_ipv4 = true  # Default: true
```

### Environment Variables

```bash
# Network configuration
export MAIN_NETWORK=wireguard  # or mycelium

# Cluster configuration
export K3S_VERSION=v1.28.5+k3s1  # K3s version
export ENABLE_METRICS=true       # Metrics server
```

---

## Available Commands

```bash
# Deploy
tfgrid-compose up --pattern k3s

# Manage
tfgrid-compose status
tfgrid-compose logs
tfgrid-compose ssh          # Connect to management node
tfgrid-compose address      # Show all IPs

# Kubernetes operations
tfgrid-compose kubectl get nodes       # Run kubectl commands
tfgrid-compose scale workers --count 5 # Scale workers
tfgrid-compose k9s                     # Launch k9s TUI

# Cleanup
tfgrid-compose down
```

---

## Application Deployment

Your app must provide Kubernetes manifests in `kubernetes/`:

### Required Manifests

**`kubernetes/deployment.yaml`**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: myapp
        image: myapp:latest
        ports:
        - containerPort: 8080
```

**`kubernetes/service.yaml`**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: myapp
spec:
  type: LoadBalancer
  selector:
    app: myapp
  ports:
  - port: 80
    targetPort: 8080
```

**`kubernetes/ingress.yaml`** (Optional)
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
spec:
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

---

## App Manifest

In your app's `tfgrid-compose.yaml`:

```yaml
name: my-k8s-app
version: 1.0.0

pattern:
  recommended: k3s
  
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
    - kubernetes/deployment.yaml
    - kubernetes/service.yaml
    - kubernetes/ingress.yaml
  helm_charts:  # Optional
    - name: postgresql
      repo: https://charts.bitnami.com/bitnami
```

---

## Examples

### Simple Microservices App

```yaml
name: microservices
pattern: k3s

resources:
  control:
    count: 1
  worker:
    count: 2

kubernetes:
  manifests:
    - kubernetes/*.yaml
```

### High-Availability SaaS

```yaml
name: saas-platform
pattern: k3s

resources:
  control:
    cpu: 4
    memory: 8192
    count: 3
  worker:
    cpu: 16
    memory: 32768
    count: 5

kubernetes:
  manifests:
    - kubernetes/app/
  helm_charts:
    - name: postgresql
    - name: redis
    - name: nginx-ingress
```

### Development Cluster

```yaml
name: dev-cluster
pattern: k3s

resources:
  control:
    cpu: 2
    memory: 4096
    count: 1
  worker:
    cpu: 4
    memory: 8192
    count: 1
```

---

## Cluster Management

### From Management Node

```bash
# Connect to management node
tfgrid-compose ssh

# Check cluster status
kubectl get nodes
kubectl get pods -A

# Deploy application
kubectl apply -f /opt/app/kubernetes/

# Use Helm
helm install myapp ./myapp-chart

# Interactive management
k9s
```

### Scaling

```bash
# Scale deployments
kubectl scale deployment myapp --replicas=5

# Scale worker nodes (infrastructure level)
# Edit infrastructure config and redeploy
nano infrastructure/credentials.auto.tfvars
# Update worker_nodes array
tfgrid-compose up
```

### Monitoring

```bash
# View logs
kubectl logs -f deployment/myapp

# Metrics
kubectl top nodes
kubectl top pods

# K9s for real-time monitoring
k9s
```

---

## Network Configuration

### WireGuard Mode (Default)

```bash
export MAIN_NETWORK=wireguard
```

- IPv4 networking
- MetalLB with IPv4 address pools
- Standard Kubernetes networking

### Mycelium Mode

```bash
export MAIN_NETWORK=mycelium
```

- Dual-stack IPv4/IPv6
- MetalLB with IPv6 address pools
- IPv6-optimized Nginx Ingress

---

## Cluster Components

### Control Plane

- **K3s Server:** Kubernetes API, scheduler, controller manager
- **etcd:** Embedded datastore (HA mode)
- **Flannel:** Pod networking

### Workers

- **K3s Agent:** Kubelet, kube-proxy
- **Container Runtime:** containerd
- **Pod Network:** Flannel VXLAN

### Add-ons

- **MetalLB:** L2/BGP load balancer
- **Nginx Ingress:** HTTP/HTTPS routing
- **Local-path Provisioner:** Storage
- **Metrics Server:** Resource metrics

---

## Troubleshooting

### Cluster not ready

```bash
# Check node status
tfgrid-compose ssh
kubectl get nodes

# Check pod status
kubectl get pods -A

# View logs
journalctl -u k3s -f
```

### Network issues

```bash
# Check Flannel
kubectl get pods -n kube-system | grep flannel

# Check connectivity
kubectl run test --image=busybox -it -- ping 10.42.0.1
```

### Storage issues

```bash
# Check PVs/PVCs
kubectl get pv
kubectl get pvc -A

# Check local-path provisioner
kubectl get pods -n kube-system | grep local-path
```

---

## Performance & Sizing

### Cluster Size Guidelines

| Workload | Control | Workers | Total Resources |
|----------|---------|---------|----------------|
| Dev/Test | 1 | 1-2 | 20-40 vCPU |
| Small Prod | 3 | 3-5 | 60-100 vCPU |
| Medium Prod | 3 | 5-10 | 100-200 vCPU |
| Large Prod | 3 | 10-20 | 200-400 vCPU |

### Resource Planning

**Control Plane:**
- Minimum: 4 vCPU, 8GB RAM
- Recommended: 8 vCPU, 16GB RAM
- HA: 3 nodes minimum

**Workers:**
- Minimum: 4 vCPU, 8GB RAM
- Recommended: 8+ vCPU, 16+ GB RAM
- Scale based on workload

---

## Security

### Best Practices

- ✅ Use private networking (no public IPs on workers)
- ✅ Enable RBAC (enabled by default)
- ✅ Regular updates (K3s, OS)
- ✅ Network policies
- ✅ Pod security policies

### Access Control

```bash
# Create service account
kubectl create serviceaccount myapp-sa

# Create RBAC role
kubectl create role myapp-role --verb=get,list,watch --resource=pods

# Bind role to SA
kubectl create rolebinding myapp-binding --role=myapp-role --serviceaccount=default:myapp-sa
```

---

## Upgrading

### K3s Version Upgrade

```bash
# From management node
cd ~/tfgrid-k3s/platform
ansible-playbook site.yml --tags=upgrade
```

### Adding Nodes

```bash
# Update infrastructure config
nano infrastructure/credentials.auto.tfvars
# Add node IDs to control_nodes or worker_nodes

# Redeploy
tfgrid-compose up
```

---

## Advanced Features

### Helm Integration

```bash
# Install chart
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install postgresql bitnami/postgresql

# List releases
helm list -A
```

### Custom Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - myapp.example.com
    secretName: myapp-tls
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
```

---

## Links

- [Pattern Contract](../PATTERN_CONTRACT.md)
- [K3s Documentation](https://docs.k3s.io/)
- [External Source](../../external-repos/tfgrid-k3s/)
- [TFGrid Compose Docs](../../docs/)

---

**Last Updated:** 2025-10-09  
**Status:** ✅ Production Ready  
**Pattern Type:** Multi-Node Kubernetes Cluster
