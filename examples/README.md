# TFGrid Compose Examples

Welcome to the TFGrid Compose examples! These are complete, working examples that you can copy and deploy.

## 📚 Available Examples

### 1. Single VM - Simple Static Website
**Path:** [`single-vm/`](./single-vm/)  
**Difficulty:** ⭐ Beginner  
**Deploy Time:** ~3 minutes

Deploy a single VM with a static website using nginx.

**Features:**
- ✅ Single VM deployment
- ✅ Static HTML website
- ✅ Public IPv4 access
- ✅ Simple bash deployment hooks

**Use Cases:**
- Landing pages
- Documentation sites
- Simple web applications

---

### 2. Gateway with SSL - Production Multi-Node
**Path:** [`gateway-ssl/`](./gateway-ssl/)  
**Difficulty:** ⭐⭐ Intermediate  
**Deploy Time:** ~5 minutes

Production-ready gateway with SSL/TLS, load balancing, and backend VMs.

**Features:**
- ✅ Gateway VM with public IPv4
- ✅ 2 backend VMs (private networking)
- ✅ Automatic SSL via Let's Encrypt
- ✅ Dual network redundancy (WireGuard + Mycelium)
- ✅ Reverse proxy & load balancing

**Use Cases:**
- Web applications with backends
- API gateways
- Microservices architecture
- High-availability services

---

### 3. K3s Cluster - Kubernetes on ThreeFold
**Path:** [`k3s-cluster/`](./k3s-cluster/)  
**Difficulty:** ⭐⭐⭐ Advanced  
**Deploy Time:** ~8 minutes

Deploy a lightweight Kubernetes cluster using K3s.

**Features:**
- ✅ 1 master node + 2 worker nodes
- ✅ Private networking between nodes
- ✅ Persistent storage support
- ✅ kubectl access configured
- ✅ Helm ready

**Use Cases:**
- Container orchestration
- Cloud-native applications
- CI/CD pipelines
- Development clusters

---

## 🚀 Quick Start

### Using an Example

1. **Copy the example:**
   ```bash
   cp -r examples/gateway-ssl my-app
   cd my-app
   ```

2. **Customize `tfgrid-compose.yaml`:**
   ```yaml
   # Update these fields:
   name: my-app-name
   nodes:
     gateway: [1, 8]  # Your node IDs
   gateway:
     domains:
       - yourdomain.com
     ssl:
       email: your@email.com
   ```

3. **Deploy:**
   ```bash
   tfgrid-compose up .
   ```

### Running Examples Directly

You can also run examples directly without copying:

```bash
cd examples/single-vm
tfgrid-compose up .
```

---

## 📖 Example Structure

Each example contains:

```
example-name/
├── README.md              # Detailed documentation
├── tfgrid-compose.yaml    # Application manifest
├── deployment/            # Deployment hooks
│   ├── setup.sh          # Install dependencies
│   ├── configure.sh      # Deploy & start app
│   └── healthcheck.sh    # Verify it works
└── src/                   # Your application code
    └── index.html
```

---

## 🔧 Customization Guide

### Change Node Selection

```yaml
nodes:
  gateway: 1        # Single node ID
  # OR
  gateway: [1, 8]   # Multiple node IDs (picks best)
```

### Adjust Resources

```yaml
resources:
  gateway:
    cpu: 4          # vCPUs
    memory: 8192    # MB (8GB)
    disk: 100       # GB
```

### Network Configuration

```yaml
network:
  main: wireguard        # How Ansible connects
  inter_node: wireguard  # Backend communication
  mode: both             # User access (both = redundancy)
```

**Options:**
- `main`: `public`, `wireguard`, `mycelium`
- `inter_node`: `wireguard`, `mycelium`
- `mode`: `wireguard-only`, `mycelium-only`, `both`

---

## 🎯 Next Steps

After deploying an example:

1. **Check status:**
   ```bash
   tfgrid-compose status .
   ```

2. **View logs:**
   ```bash
   tfgrid-compose logs .
   ```

3. **SSH into VM:**
   ```bash
   tfgrid-compose ssh .
   ```

4. **Tear down:**
   ```bash
   tfgrid-compose down .
   ```

---

## 🤝 Contributing Examples

Want to add an example? Great! Follow this structure:

1. Create directory: `examples/your-example/`
2. Add `README.md` with clear documentation
3. Include working `tfgrid-compose.yaml`
4. Add `deployment/` hooks
5. Test the deployment
6. Update this README

---

## 📚 Learn More

- [TFGrid Compose Documentation](../docs/)
- [Pattern Reference](../patterns/)
- [CLI Reference](../docs/CLI.md)
- [Troubleshooting](../docs/TROUBLESHOOTING.md)

---

## 💡 Tips

- **Start simple:** Try `single-vm` first
- **Test locally:** Validate your deployment hooks with `bash deployment/setup.sh`
- **Use version control:** Keep your customized manifests in git
- **Check logs:** If deployment fails, check `.tfgrid-compose/*.log`
