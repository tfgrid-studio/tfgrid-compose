# TFGrid Compose Troubleshooting Guide

**Version:** 0.9.0  
**Status:** Active  
**Audience:** All Users

---

## Table of Contents

1. [Common Errors](#common-errors)
2. [Debug Mode](#debug-mode)
3. [Network Issues](#network-issues)
4. [Recovery Procedures](#recovery-procedures)
5. [Log Analysis](#log-analysis)
6. [State Inspection](#state-inspection)
7. [FAQ](#faq)
8. [Getting Help](#getting-help)

---

## Common Errors

### Prerequisites Missing

#### Error: "Terraform/OpenTofu not found"

**Cause:** Neither OpenTofu nor Terraform is installed

**Solution:**
```bash
# Option 1: Install OpenTofu (recommended, open source)
# Ubuntu/Debian
curl -L https://get.opentofu.org/install-opentofu.sh | sudo bash

# macOS
brew install opentofu

# Option 2: Install Terraform
# Ubuntu/Debian
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# macOS
brew install terraform
```

**Verify:**
```bash
tofu --version
# or
terraform --version
```

---

#### Error: "Ansible not found"

**Cause:** Ansible is not installed

**Solution:**
```bash
# Ubuntu/Debian
sudo apt update
sudo apt install ansible

# macOS
brew install ansible

# Verify
ansible --version
```

---

#### Error: "ThreeFold mnemonic not found"

**Cause:** Mnemonic phrase not configured

**Solution:**
```bash
# Option 1: Standard location (recommended)
mkdir -p ~/.config/threefold
echo 'your twelve word mnemonic phrase here' > ~/.config/threefold/mnemonic
chmod 600 ~/.config/threefold/mnemonic

# Option 2: Environment variable
export TF_VAR_mnemonic="your twelve word mnemonic phrase here"

# Option 3: Project-specific (git-ignored)
echo 'your mnemonic' > .tfgrid-mnemonic
chmod 600 .tfgrid-mnemonic
```

**Security Warning:**
- Never commit mnemonic to version control
- Use 600 permissions (owner read/write only)
- Rotate regularly

---

### Deployment Errors

#### Error: "Existing deployment detected"

**Cause:** Attempting to deploy while another deployment exists

**Current Behavior:**
```
❌ Existing deployment detected
   App: my-app (pattern: single-vm)
   Status: running
   Primary IP: 10.1.3.2

Cannot deploy another app while deployment exists.
```

**Solution:**
```bash
# Option 1: Destroy existing deployment
tfgrid-compose down <existing-app-path>

# Option 2: Use different app directory
cd ../another-app
tfgrid-compose up .

# Future (v0.10.0+): Multi-deployment support
tfgrid-compose up --id=project-2 <app-path>
```

---

#### Error: "App manifest not found"

**Cause:** `tfgrid-compose.yaml` is missing

**Solution:**
```bash
# Create manifest
cat > tfgrid-compose.yaml << EOF
name: my-app
version: 1.0.0
pattern: single-vm

config:
  node: 8
  cpu: 4
  memory: 8192
  disk: 102400
EOF
```

**Required Fields:**
- `name`: Application name
- `pattern`: Deployment pattern (single-vm, gateway, k3s)
- `config`: Pattern-specific configuration

---

#### Error: "Pattern directory not found"

**Cause:** Referenced pattern doesn't exist

**Solution:**
```bash
# List available patterns
ls patterns/
# Output: single-vm  gateway  k3s

# Update manifest to use existing pattern
# Edit tfgrid-compose.yaml:
pattern: single-vm  # Use one of: single-vm, gateway, k3s
```

---

### Terraform/OpenTofu Errors

#### Error: "terraform init failed"

**Cause:** Network issues, provider errors, or invalid configuration

**Debug:**
```bash
# Check log
cat .tfgrid-compose/terraform-init.log

# Common issues:
# 1. Network connectivity
ping github.com

# 2. Provider version conflict
rm -rf .tfgrid-compose/terraform/.terraform
tfgrid-compose up <app>

# 3. Invalid Terraform version
tofu --version  # Should be >= 1.6.0
terraform --version  # Should be >= 1.5.0
```

---

#### Error: "No suitable nodes found"

**Cause:** ThreeFold Grid node unavailable or insufficient resources

**Solution:**
```bash
# Option 1: Try different node
# Edit tfgrid-compose.yaml:
config:
  node: 12  # Try different node ID

# Option 2: Check node availability
# Visit: https://dashboard.grid.tf/
# Find available nodes in your region

# Option 3: Reduce resource requirements
config:
  cpu: 2      # Reduce from 4
  memory: 4096  # Reduce from 8192
```

---

#### Error: "terraform apply failed"

**Cause:** Various infrastructure provisioning issues

**Debug:**
```bash
# Check detailed log
cat .tfgrid-compose/terraform-apply.log

# Common causes:
# 1. Insufficient funds on ThreeFold wallet
# 2. Node offline/unavailable
# 3. Resource limits exceeded
# 4. Network configuration errors

# Manual inspection
cd .tfgrid-compose/terraform
tofu plan  # See what would be created
tofu console  # Interactive inspection
```

---

### Network Errors

#### Error: "WireGuard connection failed"

**Cause:** WireGuard not installed, firewall blocking, or configuration issue

**Solution:**
```bash
# 1. Check WireGuard installed
which wg-quick
# If missing:
# Ubuntu/Debian
sudo apt install wireguard

# macOS
brew install wireguard-tools

# 2. Check interface status
sudo wg show

# 3. Check firewall
# Ubuntu/Debian
sudo ufw status
sudo ufw allow 51820/udp

# macOS
# Check System Preferences > Security & Privacy > Firewall

# 4. Restart WireGuard
sudo wg-quick down wg0
tfgrid-compose up <app>  # Will recreate WireGuard
```

---

#### Error: "SSH connection timeout"

**Cause:** VM not ready, network issue, or wrong IP

**Debug:**
```bash
# 1. Check VM IP
cat .tfgrid-compose/state.yaml | grep primary_ip

# 2. Test connectivity
ping <primary-ip>

# 3. If using WireGuard, check interface
sudo wg show
# Should show: wg0 interface with peer

# 4. Check VM is running
# Visit ThreeFold Dashboard
# https://dashboard.grid.tf/

# 5. Wait longer (VM may still be booting)
# Typical boot time: 30-90 seconds

# 6. Manual SSH test
ssh root@<primary-ip>
```

**Common Causes:**
- VM still booting (wait 2-3 minutes)
- WireGuard interface down
- Firewall blocking port 22
- Wrong IP address in state

---

#### Error: "Cannot establish SSH connection"

**Cause:** SSH keys not configured or VM doesn't have key

**Solution:**
```bash
# 1. Check SSH key exists
ls ~/.ssh/id_*.pub
# If missing, create one:
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

# 2. Verify key was deployed
# Check Terraform outputs
cd .tfgrid-compose/terraform
tofu output
# Should show ssh_key was set

# 3. Redeploy with correct key
tfgrid-compose down <app>
tfgrid-compose up <app>
```

---

### Ansible Errors

#### Error: "Ansible playbook failed"

**Cause:** Configuration errors, package installation failures

**Debug:**
```bash
# 1. Check Ansible log
cat .tfgrid-compose/ansible.log

# 2. Test connectivity
ansible all -i .tfgrid-compose/inventory.ini -m ping

# 3. Run playbook manually with verbosity
cd <pattern>/platform
ansible-playbook -i ../../.tfgrid-compose/inventory.ini site.yml -vvv

# 4. Common issues:
# - Package repository errors (apt update failed)
# - Network connectivity from VM
# - Disk space issues on VM
```

---

## Debug Mode

### Enabling Debug Mode

**Current (v0.9.0):**
```bash
# Enable bash trace mode
set -x
tfgrid-compose up <app>
set +x
```

**Future (v0.10.0+):**
```bash
# Built-in debug flag
tfgrid-compose --debug up <app>
```

### Debug Output

**What you'll see:**
- Every command executed (`+ command args`)
- Variable expansions
- Function calls
- Exit codes

**Example:**
```bash
+ log_step 'Deploying infrastructure...'
+ echo -e '\033[0;35m▶\033[0m Deploying infrastructure...'
▶ Deploying infrastructure...
+ cd .tfgrid-compose/terraform
+ tofu init
Initializing the backend...
...
```

### Debug Checklist

When debugging, check:
1. **Prerequisites:** All tools installed?
2. **Mnemonic:** Is it loaded correctly?
3. **Network:** Can you reach ThreeFold Grid?
4. **State:** Is state directory corrupt?
5. **Logs:** What do the logs say?
6. **Permissions:** Correct file permissions?

---

## Network Issues

### WireGuard Troubleshooting

**Check WireGuard Status:**
```bash
# List all interfaces
sudo wg show

# Check specific interface
sudo wg show wg0

# Expected output:
interface: wg0
  public key: ...
  private key: (hidden)
  listening port: 51820

peer: ...
  endpoint: <node-ip>:51820
  allowed ips: 10.1.0.0/16
  latest handshake: 5 seconds ago
  transfer: 1.2 MiB received, 0.8 MiB sent
```

**Common Issues:**

**1. No handshake:**
```bash
# Latest handshake: never
# Cause: Firewall blocking UDP/51820

# Solution: Allow UDP traffic
sudo ufw allow 51820/udp
```

**2. Interface conflicts:**
```bash
# Error: wg0 already exists

# Solution: Use different interface
sudo wg-quick down wg0
# Or manually specify in pattern
```

**3. Permission denied:**
```bash
# Error: Operation not permitted

# Solution: Run with sudo
sudo wg-quick up wg0
```

**WireGuard Cleanup:**
```bash
# Stop all WireGuard interfaces
sudo wg-quick down wg0
sudo wg-quick down wg1

# Remove configuration
sudo rm -f /etc/wireguard/wg*.conf
```

---

### Mycelium Troubleshooting

**Check Mycelium Status:**
```bash
# Check if Mycelium is running
ps aux | grep mycelium

# Check Mycelium connectivity
ping6 <mycelium-ipv6-from-state>
```

**Install Mycelium:**
```bash
# Ubuntu/Debian
wget https://github.com/threefoldtech/mycelium/releases/latest/download/mycelium-x86_64-unknown-linux-musl.tar.gz
tar -xzf mycelium-*.tar.gz
sudo mv mycelium /usr/local/bin/
sudo chmod +x /usr/local/bin/mycelium

# Run Mycelium
sudo mycelium --peers tcp://188.40.132.242:9651
```

---

### Connectivity Testing

**Network Diagnostics:**
```bash
# 1. Test ThreeFold Grid reachability
ping grid.tf

# 2. Test DNS resolution
nslookup grid.tf

# 3. Test WireGuard peer
# Get peer endpoint from state
cat .tfgrid-compose/state.yaml | grep node
ping <node-ip>

# 4. Trace route
traceroute <primary-ip>

# 5. Test SSH port
nc -zv <primary-ip> 22
```

---

## Recovery Procedures

### State Corruption

**Symptoms:**
- Inconsistent state information
- Terraform errors about existing resources
- Deployment shows running but no VM exists

**Recovery:**
```bash
# 1. Backup current state
cp -r .tfgrid-compose .tfgrid-compose.backup

# 2. Try to destroy cleanly
tfgrid-compose down <app>

# 3. If destroy fails, manual cleanup
cd .tfgrid-compose/terraform
tofu destroy  # or terraform destroy

# 4. Clean state directory
rm -rf .tfgrid-compose/

# 5. Redeploy
tfgrid-compose up <app>
```

---

### Stuck Deployment

**Symptoms:**
- Deployment running but not progressing
- Process hung on specific step
- No error messages

**Recovery:**
```bash
# 1. Stop the stuck process
# Press Ctrl+C

# 2. Check what's running
ps aux | grep tfgrid-compose
ps aux | grep terraform
ps aux | grep ansible

# 3. Kill if necessary
killall terraform
killall ansible-playbook

# 4. Check state
cat .tfgrid-compose/state.yaml

# 5. Decide: retry or destroy
# Retry:
tfgrid-compose up <app>

# Destroy:
tfgrid-compose down <app>
```

---

### Orphaned Resources

**Symptoms:**
- Resources exist on ThreeFold Grid but not in state
- Billing continues but no deployment shown

**Recovery:**
```bash
# 1. Check ThreeFold Dashboard
# Visit: https://dashboard.grid.tf/
# Login with your account
# View active deployments

# 2. Import existing resources (manual)
cd .tfgrid-compose/terraform
tofu import <resource-type>.<resource-name> <resource-id>

# 3. Or delete via Dashboard
# ThreeFold Dashboard > Deployments > Delete

# 4. Clean local state
rm -rf .tfgrid-compose/
```

---

### WireGuard Cleanup

**When to clean:**
- Deployment destroyed but WireGuard still running
- Interface conflicts
- Network issues

**Cleanup:**
```bash
# 1. List all interfaces
sudo wg show

# 2. Stop tfgrid-compose interfaces (wg0, wg1, etc.)
sudo wg-quick down wg0
sudo wg-quick down wg1

# 3. Remove configurations
sudo rm -f /etc/wireguard/wg*.conf

# 4. Verify cleanup
sudo wg show  # Should show nothing
```

---

## Log Analysis

### Log Locations

All logs stored in `.tfgrid-compose/`:

```
.tfgrid-compose/
├── terraform-init.log      # Terraform initialization
├── terraform-plan.log      # Terraform plan output
├── terraform-apply.log     # Terraform apply (deployment)
├── terraform-destroy.log   # Terraform destroy
├── ansible.log            # Ansible playbook execution
├── hook-setup.log         # Setup hook output (if exists)
├── hook-configure.log     # Configure hook output
└── hook-healthcheck.log   # Health check output
```

### Reading Logs

**Terraform Logs:**
```bash
# Check for errors in Terraform apply
cat .tfgrid-compose/terraform-apply.log | grep -i error

# Check last 50 lines
tail -50 .tfgrid-compose/terraform-apply.log

# Real-time monitoring
tail -f .tfgrid-compose/terraform-apply.log
```

**Ansible Logs:**
```bash
# Check for failed tasks
cat .tfgrid-compose/ansible.log | grep -i "failed:"

# Check for warnings
cat .tfgrid-compose/ansible.log | grep -i "warn"

# Extract summary
cat .tfgrid-compose/ansible.log | grep "PLAY RECAP" -A 5
```

**Hook Logs:**
```bash
# Check setup hook
cat .tfgrid-compose/hook-setup.log

# All hooks
tail -n 20 .tfgrid-compose/hook-*.log
```

---

## State Inspection

### Viewing State

**State File:**
```bash
# View full state
cat .tfgrid-compose/state.yaml

# Pretty print (if yq installed)
yq . .tfgrid-compose/state.yaml

# Extract specific values
grep primary_ip .tfgrid-compose/state.yaml
grep deployment_name .tfgrid-compose/state.yaml
```

**Terraform State:**
```bash
cd .tfgrid-compose/terraform

# Show all resources
tofu show

# List resources
tofu state list

# Show specific resource
tofu state show grid_deployment.vm

# Extract outputs
tofu output
tofu output primary_ip
tofu output -json  # JSON format
```

### State Validation

**Check State Integrity:**
```bash
# 1. Verify state file exists
test -f .tfgrid-compose/state.yaml && echo "OK" || echo "Missing"

# 2. Check required fields
grep -q "primary_ip:" .tfgrid-compose/state.yaml && echo "IP OK"
grep -q "deployment_name:" .tfgrid-compose/state.yaml && echo "Name OK"

# 3. Verify Terraform state
cd .tfgrid-compose/terraform
tofu validate
tofu plan  # Should show "No changes"
```

---

## FAQ

### General

**Q: Can I deploy multiple apps at once?**  
**A:** Currently (v0.9.0), only one deployment per directory. Multi-deployment support coming in v0.10.0.

**Workaround:**
```bash
# Use separate directories
cd ~/projects/app1
tfgrid-compose up .

cd ~/projects/app2
tfgrid-compose up .
```

---

**Q: How do I update my deployment?**  
**A:** Destroy and redeploy:
```bash
tfgrid-compose down <app>
tfgrid-compose up <app>
```

Future (v0.11.0): `tfgrid-compose update <app>` for in-place updates

---

**Q: Can I use my own SSH key?**  
**A:** Yes, tfgrid-compose automatically uses keys from `~/.ssh/`:
```bash
# Uses these keys (in order):
~/.ssh/id_ed25519.pub
~/.ssh/id_rsa.pub
~/.ssh/id_ecdsa.pub
```

To use specific key, set in pattern config.

---

**Q: How much does deployment cost?**  
**A:** Depends on resources:
- VM: ~$2-10/month
- Storage: ~$0.15/GB/month
- Network: Usually included

Check ThreeFold pricing: https://threefold.io/pricing

---

### Technical

**Q: OpenTofu vs Terraform - which should I use?**  
**A:** OpenTofu is recommended:
- Open source (Apache 2.0)
- Community-driven
- Compatible with Terraform
- No license restrictions

tfgrid-compose automatically detects and prefers OpenTofu.

---

**Q: Can I customize the Ansible playbook?**  
**A:** Yes! Each pattern has a platform/ directory:
```bash
patterns/single-vm/platform/
└── site.yml  # Main playbook

# Copy pattern and modify:
cp -r patterns/single-vm patterns/my-custom
# Edit patterns/my-custom/platform/site.yml
# Use: pattern: my-custom
```

---

**Q: How do I add custom packages?**  
**A:** Use app hooks:
```yaml
# tfgrid-compose.yaml
hooks:
  setup: ./deployment/hooks/setup.sh
```

```bash
# deployment/hooks/setup.sh
#!/bin/bash
apt update
apt install -y python3 nodejs npm
```

---

**Q: Can I use a different region/node?**  
**A:** Yes, specify in config:
```yaml
# tfgrid-compose.yaml
config:
  node: 142  # Different node ID
```

Find nodes: https://dashboard.grid.tf/

---

**Q: How do I access the VM?**  
**A:** Via SSH:
```bash
# Get IP from state
cat .tfgrid-compose/state.yaml | grep primary_ip

# SSH in
ssh root@<primary-ip>

# Or use helper command
tfgrid-compose ssh <app>
```

---

**Q: Can I use this for production?**  
**A:** Yes! tfgrid-compose v0.9.0 is production-ready. Recommendations:
- Use gateway pattern for web apps (public IP + SSL)
- Enable monitoring
- Set up backups
- Use version control for configuration
- Test deployments in staging first

---

### Troubleshooting

**Q: Deployment takes too long**  
**A:** Typical times:
- Infrastructure: 30-60s
- Network setup: 5-10s
- SSH wait: 30-90s
- Platform config: 60-120s
- Total: 2-5 minutes

If longer:
- Check node availability (may be slow/busy)
- Check network connectivity
- Try different node

---

**Q: "Connection refused" on SSH**  
**A:** VM may still be booting:
```bash
# Wait 2-3 minutes then retry
sleep 120
ssh root@<primary-ip>

# Check VM status via Dashboard
```

---

**Q: How do I change VM resources after deployment?**  
**A:** Currently requires redeploy:
```bash
# 1. Update config
# Edit tfgrid-compose.yaml:
config:
  cpu: 8     # Increased
  memory: 16384

# 2. Redeploy
tfgrid-compose down <app>
tfgrid-compose up <app>
```

Future: In-place resource updates

---

**Q: WireGuard says "permission denied"**  
**A:** WireGuard requires root:
```bash
# Check if sudo is needed
sudo wg show

# tfgrid-compose will prompt for sudo when needed
```

---

## Getting Help

### Before Asking

1. **Check logs:**
   ```bash
   tail -50 .tfgrid-compose/*.log
   ```

2. **Search documentation:**
   - [Architecture](ARCHITECTURE.md)
   - [Quick Start](QUICKSTART.md)
   - [Pattern Contract](../patterns/PATTERN_CONTRACT.md)

3. **Check state:**
   ```bash
   cat .tfgrid-compose/state.yaml
   ```

---

### Reporting Issues

**Include in bug reports:**

1. **Environment:**
   ```bash
   # OS and version
   uname -a
   
   # tfgrid-compose version
   tfgrid-compose --version
   
   # Tool versions
   tofu --version || terraform --version
   ansible --version
   ```

2. **Full error output:**
   ```bash
   # Redacted mnemonic!
   cat .tfgrid-compose/terraform-apply.log
   ```

3. **Steps to reproduce**

4. **Configuration:**
   ```yaml
   # tfgrid-compose.yaml (redact sensitive data)
   ```

---

### Support Channels

**GitHub Issues:**
- Bug reports: https://github.com/tfgrid-studio/tfgrid-compose/issues
- Feature requests: Label as "enhancement"

**Discussions:**
- Questions: https://github.com/orgs/tfgrid-studio/discussions
- Community help

**Documentation:**
- Docs site: https://docs.tfgrid.studio
- GitHub: https://github.com/tfgrid-studio

**ThreeFold Resources:**
- ThreeFold Manual: https://manual.grid.tf/
- ThreeFold Forum: https://forum.threefold.io/
- ThreeFold Support: https://threefold.io/support

---

## Quick Reference

### Common Commands

```bash
# Deploy
tfgrid-compose up <app-path>

# Status
tfgrid-compose status <app-path>

# SSH
tfgrid-compose ssh <app-path>

# Execute command
tfgrid-compose exec <app-path> <command>

# Destroy
tfgrid-compose down <app-path>

# Clean state
rm -rf .tfgrid-compose/

# Check logs
tail -f .tfgrid-compose/terraform-apply.log
tail -f .tfgrid-compose/ansible.log
```

### Emergency Recovery

```bash
# Nuclear option: clean everything
tfgrid-compose down <app>
rm -rf .tfgrid-compose/
sudo wg-quick down wg0 2>/dev/null || true
sudo rm -f /etc/wireguard/wg*.conf

# Then try fresh deployment
tfgrid-compose up <app>
```

---

**Document Status:** Active  
**Last Updated:** 2025-10-14  
**Next Review:** After user feedback from v0.9.0 release
