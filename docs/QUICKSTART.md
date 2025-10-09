# Quick Start Guide - TFGrid Compose

Deploy your first application on ThreeFold Grid in **5 minutes**.

---

## Prerequisites

Before you begin, ensure you have:

- ✅ **Operating System:** Linux or macOS
- ✅ **ThreeFold Account:** Grid account with TFT balance
- ✅ **Mnemonic:** Your ThreeFold Grid mnemonic phrase
- ✅ **Tools Installed:**
  - Git
  - Terraform (or OpenTofu)
  - Ansible
  - SSH client
  - WireGuard (for private networking)

---

## Installation

### 1. Install Required Tools

**Ubuntu/Debian:**
```bash
# Terraform
wget https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip
unzip terraform_1.5.7_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```bash
git clone https://github.com/tfgrid-studio/tfgrid-compose
cd tfgrid-compose
```

### 3. Configure Your Credentials

```bash
# Create config directory
mkdir -p ~/.config/threefold

# Add your mnemonic (replace with your actual mnemonic)
echo "word1 word2 word3 ... word12" > ~/.config/threefold/mnemonic

# Secure the file
chmod 600 ~/.config/threefold/mnemonic
```

**⚠️ Security Note:** Keep your mnemonic secure. Never commit it to git or share it.

---

## Your First Deployment

### Deploy the AI Agent Example

```bash
# Deploy the application
make up APP=../tfgrid-ai-agent
```

**What happens:**
1. ✅ Validates your configuration
2. 🏗️ Creates VM infrastructure on ThreeFold Grid
3. 🔐 Sets up WireGuard networking
4. ⚙️ Configures the VM with Ansible
5. 🚀 Deploys the application

**Expected time:** 2-3 minutes

### Check Deployment Status

```bash
# View deployment information
make status APP=../tfgrid-ai-agent

# SSH into your deployment
make ssh APP=../tfgrid-ai-agent

# View IP addresses
make address APP=../tfgrid-ai-agent
```

### Clean Up

```bash
# Destroy the deployment
make down APP=../tfgrid-ai-agent

# Clean local state
make clean
```

---

## Common Commands

### Deployment
```bash
make up APP=<app-path>      # Deploy an application
make down APP=<app-path>    # Destroy deployment
make status APP=<app-path>  # Check deployment status
```

### Management
```bash
make ssh APP=<app-path>     # SSH into VM
make logs APP=<app-path>    # View application logs
make address APP=<app-path> # Show IP addresses
```

### Debugging
```bash
make wg                     # Setup WireGuard only
make wait-ssh               # Wait for SSH readiness
make inventory              # Generate Ansible inventory
make ansible                # Run Ansible only
```

### Utilities
```bash
make patterns               # List available patterns
make help                   # Show all commands
make clean                  # Clean local state
```

---

## Troubleshooting

### ❌ "Terraform not found"

**Solution:**
```bash
# Install Terraform (see Installation section above)
terraform --version
```

### ❌ "Ansible not found"

**Solution:**
```bash
# Ubuntu/Debian
sudo apt install ansible

# macOS
brew install ansible
```

### ❌ "No mnemonic found"

**Solution:**
```bash
# Create the config directory and add your mnemonic
mkdir -p ~/.config/threefold
echo "your twelve word mnemonic phrase here" > ~/.config/threefold/mnemonic
chmod 600 ~/.config/threefold/mnemonic
```

### ❌ "WireGuard setup failed"

**Solution:**
```bash
# Install WireGuard
# Ubuntu/Debian
sudo apt install wireguard

# macOS
brew install wireguard-tools

# Verify
sudo wg show
```

### ❌ "SSH connection timeout"

**Causes:**
- VM still booting (wait 1-2 minutes)
- WireGuard not connected
- Network issues

**Solution:**
```bash
# Check WireGuard is up
sudo wg show

# Check you can ping the VM
ping -c 3 <vm-ip>

# Retry SSH wait
make wait-ssh
```

### ❌ "Deployment already exists"

**Solution:**
```bash
# Destroy existing deployment first
make down APP=<app-path>

# Or clean state if deployment was manually deleted
make clean

# Then try again
make up APP=<app-path>
```

---

## Understanding Patterns

TFGrid Compose uses **patterns** to define deployment architectures:

### Available Patterns

**1. single-vm** (Default)
- One VM with private networking
- WireGuard or Mycelium access
- Best for: Development, databases, internal services

**2. gateway** (Coming Soon)
- Gateway VM with public IPv4
- Backend VMs with private networking
- Best for: Production web apps, e-commerce

**3. k3s** (Coming Soon)
- Kubernetes cluster (K3s)
- Master + worker nodes
- Best for: Cloud-native apps, microservices

---

## Next Steps

### Deploy More Apps

Explore the available applications:
```bash
# List patterns
make patterns

# Deploy different apps
make up APP=../tfgrid-gateway
make up APP=../tfgrid-k3s
```

### Create Your Own App

See [Creating Apps Guide](./CREATING_APPS.md) to learn how to:
1. Create a `tfgrid-compose.yaml` manifest
2. Define deployment hooks
3. Package your application

### Learn More

- **[User Guide](./USER_GUIDE.md)** - Complete command reference
- **[Patterns Guide](./PATTERNS.md)** - Choosing the right pattern
- **[Troubleshooting](./TROUBLESHOOTING.md)** - Common issues & solutions
- **[FAQ](./FAQ.md)** - Frequently asked questions

---

## Getting Help

**Found a bug?** [Open an issue](https://github.com/tfgrid-studio/tfgrid-compose/issues)

**Need help?** [Join our community](https://forum.threefold.io)

**Contributing?** See [CONTRIBUTING.md](../.github/CONTRIBUTING.md)

---

## Example: Complete Workflow

```bash
# 1. Clone the repository
git clone https://github.com/tfgrid-studio/tfgrid-compose
cd tfgrid-compose

# 2. Configure credentials
mkdir -p ~/.config/threefold
echo "your mnemonic here" > ~/.config/threefold/mnemonic

# 3. Deploy
make up APP=../tfgrid-ai-agent

# 4. Verify
make status APP=../tfgrid-ai-agent

# 5. Use it
make ssh APP=../tfgrid-ai-agent

# 6. Clean up when done
make down APP=../tfgrid-ai-agent
```

---

**🎉 You're ready to deploy on ThreeFold Grid!**

For more advanced usage, continue to the [User Guide](./USER_GUIDE.md).
