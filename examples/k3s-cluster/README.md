# K3s Cluster Example

Deploy a lightweight Kubernetes cluster using K3s.

## Overview

This example deploys a production-ready K3s cluster:
- **1 Master Node** - K3s control plane
- **2 Worker Nodes** - Application workloads
- **Private Networking** - WireGuard mesh between nodes
- **Ingress Ready** - Traefik included
- **kubectl Access** - Remote cluster management

## Features

- ✅ K3s lightweight Kubernetes
- ✅ Multi-node cluster (1 master + 2 workers)
- ✅ Private networking (WireGuard)
- ✅ Traefik ingress controller
- ✅ ServiceLB load balancer
- ✅ Metrics server
- ✅ kubectl configuration auto-generated

## Prerequisites

- ThreeFold mnemonic configured (`~/.config/threefold/mnemonic`)
- kubectl installed locally (`brew install kubectl` or `apt install kubectl`)
- WireGuard installed (`sudo apt install wireguard`)

## Quick Start

### 1. Copy and Customize

```bash
cp -r examples/k3s-cluster my-cluster
cd my-cluster
```

Edit `tfgrid-compose.yaml`:

```yaml
name: my-k3s-cluster
version: 1.0.0

nodes:
  master: 1          # Your master node ID
  workers: [8, 13]   # Your worker node IDs

k3s:
  token_secret: "your-secure-random-token-here"
```

### 2. Deploy

```bash
tfgrid-compose up .
```

Deployment takes ~8 minutes.

### 3. Configure kubectl

After deployment, get kubeconfig:

```bash
# Copy kubeconfig from .tfgrid-compose/
export KUBECONFIG=$(pwd)/.tfgrid-compose/kubeconfig.yaml

# Test access
kubectl get nodes
```

### 4. Deploy Applications

```bash
kubectl apply -f manifests/
```

## Management

```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# SSH to master
tfgrid-compose ssh .

# Tear down cluster
tfgrid-compose down .
```

## Example Workload

Deploy a simple nginx:

```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer
kubectl get svc nginx
```

## Next Steps

- Deploy your applications in `manifests/`
- Configure persistent storage
- Set up ingress rules for your services
- Add more worker nodes

## Learn More

- [TFGrid Compose Documentation](../../docs/)
- [K3s Pattern Reference](../../patterns/k3s/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## Note

This example requires the K3s pattern to be implemented. Check pattern availability with:

```bash
tfgrid-compose patterns
```
