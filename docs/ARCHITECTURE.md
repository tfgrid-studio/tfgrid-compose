# TFGrid Compose Architecture

**Version:** 0.9.0  
**Status:** Active  
**Audience:** Developers, Contributors, Advanced Users

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Core Components](#core-components)
3. [Data Flow](#data-flow)
4. [Pattern System](#pattern-system)
5. [State Management](#state-management)
6. [Extension Guide](#extension-guide)
7. [Design Decisions](#design-decisions)
8. [Performance Considerations](#performance-considerations)

---

## System Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     tfgrid-compose CLI                      │
│                    (User Entry Point)                       │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│                    Core Orchestrator                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Validation → Pattern Loading → App Loading          │   │
│  │       ↓            ↓               ↓                 │   │
│  │  Infrastructure → Network → Platform → App Deploy    │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────┬────────────────────────────┬──────────────────┘
              │                            │
              ▼                            ▼
┌──────────────────────────┐  ┌──────────────────────────┐
│   Pattern System         │  │   Task Executors         │
│  ┌────────────────────┐  │  │  ┌────────────────────┐  │
│  │ Infrastructure/    │  │  │  │ terraform.sh       │  │
│  │ Platform/          │  │  │  │ wireguard.sh       │  │
│  │ App/               │  │  │  │ ansible.sh         │  │
│  └────────────────────┘  │  │  └────────────────────┘  │
└──────────────────────────┘  └──────────────────────────┘
              │                            │
              ▼                            ▼
┌─────────────────────────────────────────────────────────────┐
│                     ThreeFold Grid                          │
│  ┌────────────┐    ┌────────────┐  ┌──────────────────┐     │
│  │   Nodes    │    │  Network   │  │  Storage/ZDB     │     │
│  └────────────┘    └────────────┘  └──────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### Design Philosophy

**1. Pattern-Based Architecture**
- Patterns encapsulate infrastructure, platform, and application concerns
- Orchestrator is pattern-agnostic (knows nothing about pattern internals)
- New patterns can be added without modifying core code

**2. Contract-Driven Integration**
- Patterns must implement a [standard contract](../patterns/PATTERN_CONTRACT.md)
- Orchestrator consumes contract outputs (primary_ip, deployment_name, etc.)
- Loose coupling enables extensibility

**3. Shell-Based Implementation**
- Bash scripts for simplicity and transparency
- Easy to understand, debug, and extend
- Minimal dependencies (bash, common Unix tools)
- Works on any Unix-like system (Linux, macOS)

---

## Core Components

### 1. CLI Entry Point (`cli/tfgrid-compose`)

**Purpose:** User-facing command interface

**Responsibilities:**
- Parse command-line arguments
- Load context file (`.tfgrid-compose.yaml`)
- Route commands to appropriate handlers
- Display help and version information

**Key Features:**
- Context file support for simplified commands
- Command aliases (e.g., `agent` subcommand)
- Global flags (--debug, --version)

**Example Flow:**
```bash
tfgrid-compose up /path/to/app
    ↓
Load context (optional)
    ↓
Validate prerequisites
    ↓
Call orchestrator.deploy_app()
```

---

### 2. Common Utilities (`core/common.sh`)

**Purpose:** Shared functions used across all modules

**Key Functions:**

```bash
# Logging
log_info()      # Informational messages
log_success()   # Success indicators
log_warning()   # Warnings
log_error()     # Errors
log_step()      # Major steps

# Utilities
command_exists()    # Check if command is available
yaml_get()          # Extract values from YAML files
state_save()        # Save to state file
state_get()         # Retrieve from state file
state_clear()       # Clear state directory
```

**Color-Coded Output:**
- 🔵 Blue: Informational
- ✅ Green: Success
- ⚠️ Yellow: Warnings
- ❌ Red: Errors
- ▶ Purple: Major steps

---

### 3. Validation Module (`core/validation.sh`)

**Purpose:** Validate prerequisites and configurations

**Validation Stages:**

```bash
validate_prerequisites()
    ├── Check OpenTofu/Terraform (prefer OpenTofu)
    ├── Check Ansible
    ├── Check SSH client
    ├── Check WireGuard (optional warning)
    ├── Load ThreeFold mnemonic
    └── Export TF_CMD environment variable

validate_app_path()
    ├── Check directory exists
    └── Check tfgrid-compose.yaml exists

validate_deployment_exists()
    ├── Check .tfgrid-compose/ directory
    └── Check state.yaml file

validate_no_deployment()
    └── Prevent duplicate deployments

validate_network_prerequisites()
    ├── Check WireGuard (if needed)
    ├── Check Mycelium (if needed)
    └── Test connectivity
```

**Mnemonic Loading Priority:**
1. Environment variable: `$TF_VAR_mnemonic`
2. Standard location: `~/.config/threefold/mnemonic`
3. Project-specific: `./.tfgrid-mnemonic`

**OpenTofu Priority:**
```bash
# Check tofu first (open source)
if command -v tofu; then
    export TF_CMD="tofu"
elif command -v terraform; then
    export TF_CMD="terraform"
else
    error "Neither found"
fi
```

---

### 4. Pattern Loader (`core/pattern-loader.sh`)

**Purpose:** Load and validate deployment patterns

**Pattern Structure:**
```
patterns/
└── single-vm/
    ├── pattern.yaml           # Pattern metadata
    ├── infrastructure/        # Terraform/OpenTofu files
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf        # MUST implement contract
    ├── platform/             # Ansible playbooks
    │   ├── site.yml
    │   └── roles/
    └── README.md
```

**Pattern Loading Flow:**
```bash
load_pattern()
    ├── Read pattern name from app manifest
    ├── Validate pattern directory exists
    ├── Load pattern.yaml metadata
    ├── Verify infrastructure/ (Terraform files)
    ├── Verify platform/ (Ansible playbooks)
    └── Export pattern variables
```

**Pattern Metadata (`pattern.yaml`):**
```yaml
name: single-vm
version: 1.0.0
description: Single VM deployment
requires:
  - terraform  # or opentofu
  - ansible
  - wireguard  # optional
```

---

### 5. App Loader (`core/app-loader.sh`)

**Purpose:** Load and validate application manifests

**App Manifest (`tfgrid-compose.yaml`):**
```yaml
name: my-app
version: 1.0.0
pattern: single-vm

# Pattern configuration
config:
  node: 8
  cpu: 4
  memory: 8192
  disk: 102400
  
# Optional app-specific hooks
hooks:
  setup: ./deployment/hooks/setup.sh
  configure: ./deployment/hooks/configure.sh
  healthcheck: ./deployment/hooks/healthcheck.sh
```

**App Loading Flow:**
```bash
load_app()
    ├── Parse tfgrid-compose.yaml
    ├── Extract app metadata
    ├── Load pattern configuration
    ├── Validate hooks (if present)
    └── Export app variables
```

---

### 6. Orchestrator (`core/orchestrator.sh`)

**Purpose:** Main deployment orchestration logic

**Deployment Flow:**

```bash
deploy_app()
    │
    ├─ 1. VALIDATION PHASE
    │      ├── Validate system prerequisites
    │      ├── Validate no existing deployment
    │      ├── Validate app path and manifest
    │      └── Load pattern and app config
    │
    ├─ 2. INFRASTRUCTURE PHASE
    │      ├── Generate Terraform config
    │      ├── Run: terraform init
    │      ├── Run: terraform plan
    │      ├── Run: terraform apply
    │      └── Extract outputs (primary_ip, node_ids, etc.)
    │
    ├─ 3. NETWORK PHASE
    │      ├── If primary_ip_type == "wireguard":
    │      │    ├── Extract WireGuard config
    │      │    ├── Deploy to /etc/wireguard/
    │      │    └── Start wg-quick up
    │      └── Test connectivity
    │
    ├─ 4. WAIT PHASE
    │      ├── Wait for SSH (up to 5 minutes)
    │      ├── Retry connection every 10 seconds
    │      └── Verify SSH access
    │
    ├─ 5. PLATFORM PHASE
    │      ├── Generate Ansible inventory
    │      ├── Run: ansible-playbook site.yml
    │      └── Configure base system
    │
    ├─ 6. APPLICATION PHASE
    │      ├── Copy app source to VM
    │      ├── Run setup hook (if present)
    │      ├── Run configure hook (if present)
    │      └── Run healthcheck hook (if present)
    │
    ├─ 7. VERIFICATION PHASE
    │      ├── Test SSH connectivity
    │      ├── Check application service
    │      └── Validate deployment
    │
    └─ 8. FINALIZATION
           ├── Save deployment metadata
           ├── Display connection info
           └── Show next steps
```

**Destroy Flow:**
```bash
destroy_deployment()
    ├── Validate deployment exists
    ├── Stop WireGuard interface (if active)
    ├── Run: terraform destroy
    └── Clear state directory
```

---

### 7. Task Executors (`core/tasks/`)

**Purpose:** Execute specific deployment tasks

#### `terraform.sh`
```bash
# Detects OpenTofu or Terraform
TF_CMD detection (tofu → terraform → error)
    ├── terraform init
    ├── terraform plan
    ├── terraform apply
    └── Extract outputs to state.yaml
```

#### `wireguard.sh`
```bash
# Sets up WireGuard VPN
    ├── Extract wg_config from Terraform
    ├── Generate interface name (wg0, wg1, ...)
    ├── Deploy to /etc/wireguard/
    ├── Handle conflicts with existing interfaces
    └── Start interface with wg-quick
```

#### `ansible.sh`
```bash
# Configures platform
    ├── Generate inventory from state
    ├── Test connectivity
    ├── Run playbook
    └── Capture logs
```

#### `wait-ssh.sh`
```bash
# Waits for SSH to be ready
    ├── Timeout: 300 seconds (5 minutes)
    ├── Retry: Every 10 seconds
    ├── Test: ssh -o BatchMode=yes <ip> 'echo ok'
    └── Early exit on first success
```

---

## Data Flow

### State Directory Structure

```
.tfgrid-compose/
├── state.yaml                    # Deployment metadata
├── terraform/                    # Generated Terraform config
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── .terraform/              # Terraform state
│   └── terraform.tfstate
├── inventory.ini                 # Generated Ansible inventory
├── wg0.conf                     # WireGuard config (if used)
├── terraform-init.log           # Terraform init log
├── terraform-plan.log           # Terraform plan log
├── terraform-apply.log          # Terraform apply log
├── ansible.log                  # Ansible playbook log
├── hook-setup.log              # Setup hook log
├── hook-configure.log          # Configure hook log
└── hook-healthcheck.log        # Healthcheck hook log
```

### State File (`state.yaml`)

```yaml
# Metadata
app_name: my-app
app_version: 1.0.0
pattern: single-vm
deployment_id: abc123xyz
created_at: 2025-10-14T12:00:00Z

# Infrastructure outputs
vm_ip: 10.1.3.2
primary_ip: 10.1.3.2
primary_ip_type: wireguard
deployment_name: vm_abc123xyz
node_ids: [8]
mycelium_ip: 543:7233:7534:51c4:ff0f:f38b:d69b:8f19

# Network
wg_interface: wg0
network_name: net_abc123xyz

# Platform
ssh_user: root
ssh_key: /home/user/.ssh/id_ed25519

# Status
status: running
last_updated: 2025-10-14T12:05:00Z
```

### Data Flow Diagram

```
┌──────────────────┐
│  User Command    │
│  tfgrid-compose  │
│       up         │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ App Manifest     │
│ .yaml file       │───┐
└────────┬─────────┘   │
         │             │
         ▼             │
┌──────────────────┐   │
│ Pattern Files    │◄──┘
│ Infrastructure/  │
│ Platform/        │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Terraform Apply  │
│ Creates VMs      │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Extract Outputs  │
│ Save to state    │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ WireGuard Setup  │
│ Network Access   │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ Ansible Config   │
│ Platform Setup   │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ App Deployment   │
│ Hooks Execution  │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ State Saved      │
│ Deployment Done  │
└──────────────────┘
```

---

## Pattern System

### Pattern Contract

Every pattern MUST implement [the standard contract](../patterns/PATTERN_CONTRACT.md).

**Required Terraform Outputs:**
```terraform
output "primary_ip" {
  value = "10.1.3.2"
  description = "Primary IP for SSH"
}

output "primary_ip_type" {
  value = "wireguard"  # or "public" or "mycelium"
  description = "Type of primary IP"
}

output "deployment_name" {
  value = "vm_abc123"
  description = "Deployment name"
}

output "node_ids" {
  value = [8]
  description = "Node IDs used"
}
```

### Pattern Types

#### 1. Single-VM Pattern
**Use Case:** Development, databases, internal services, AI agents

**Infrastructure:**
- 1 VM on TFGrid
- WireGuard private network
- Optional Mycelium IPv6

**Network:**
- Primary: WireGuard IP (10.x.x.x)
- Secondary: Mycelium IP (IPv6)

**Platform:**
- Ubuntu 24.04
- Base packages (git, curl, build-essential)
- Docker (optional)

#### 2. Gateway Pattern
**Use Case:** Production web apps with public IPv4

**Infrastructure:**
- 1 Gateway VM (public IPv4)
- N Backend VMs (private network)
- WireGuard + Mycelium

**Network:**
- Primary: Public IPv4 (gateway)
- Secondary: WireGuard IPs (backends)

**Platform:**
- Gateway: Nginx/HAProxy reverse proxy
- Backends: Application servers
- SSL/TLS: Let's Encrypt (automated)

#### 3. K3s Pattern
**Use Case:** Kubernetes clusters

**Infrastructure:**
- 1+ Control plane nodes
- N Worker nodes
- 1 Management node (kubectl, helm, k9s)

**Network:**
- Primary: Control plane WireGuard IP
- Secondary: Worker node IPs

**Platform:**
- K3s lightweight Kubernetes
- MetalLB load balancer
- Nginx Ingress Controller
- Local-path storage provisioner

---

## State Management

### State Lifecycle

```
┌──────────────┐
│   No State   │  Initial state
└──────┬───────┘
       │
       │  deploy_app()
       ▼
┌──────────────┐
│  Deploying   │  Terraform running
└──────┬───────┘
       │
       │  Success
       ▼
┌──────────────┐
│   Running    │  Deployment active
└──────┬───────┘
       │
       │  destroy_deployment()
       ▼
┌──────────────┐
│  Destroying  │  Terraform destroy
└──────┬───────┘
       │
       │  Success
       ▼
┌──────────────┐
│   Cleaned    │  State removed
└──────────────┘
```

### State Operations

**Create State:**
```bash
create_state_dir()
    mkdir -p .tfgrid-compose
    touch .tfgrid-compose/state.yaml
```

**Save to State:**
```bash
state_save "key" "value"
    echo "key: value" >> .tfgrid-compose/state.yaml
```

**Read from State:**
```bash
state_get "key"
    grep "^key:" .tfgrid-compose/state.yaml | awk '{print $2}'
```

**Clear State:**
```bash
state_clear()
    rm -rf .tfgrid-compose/
```

### State Validation

**Check Deployment Exists:**
```bash
if [ -f ".tfgrid-compose/state.yaml" ]; then
    echo "Deployment exists"
fi
```

**Prevent Duplicate Deployments:**
```bash
validate_no_deployment()
    if deployment_exists; then
        show current deployment info
        error "Cannot deploy while another exists"
    fi
```

---

## Extension Guide

### Adding a New Pattern

**1. Create Pattern Directory:**
```bash
patterns/my-pattern/
├── pattern.yaml
├── infrastructure/
│   └── main.tf         # Implement pattern contract!
├── platform/
│   └── site.yml
└── README.md
```

**2. Implement Pattern Contract:**
```terraform
# infrastructure/outputs.tf
output "primary_ip" {
  value = your_resource.primary_ip
}

output "primary_ip_type" {
  value = "wireguard"
}

output "deployment_name" {
  value = your_resource.name
}

output "node_ids" {
  value = [var.node_id]
}
```

**3. Test Pattern:**
```bash
# Test with example app
tfgrid-compose up /path/to/test-app

# Verify outputs
cd .tfgrid-compose/terraform
terraform output primary_ip
terraform output primary_ip_type
```

**4. Document Pattern:**
```markdown
# My Pattern

## Use Cases
- What problems does this solve?

## Configuration
- What options are available?

## Example
- Show complete example
```

### Adding a New Task

**1. Create Task Script:**
```bash
core/tasks/my-task.sh
```

**2. Implement Task:**
```bash
#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

log_step "Running my task..."

# Task implementation
# ...

log_success "Task complete"
```

**3. Call from Orchestrator:**
```bash
# In core/orchestrator.sh
if ! bash "$DEPLOYER_ROOT/core/tasks/my-task.sh"; then
    log_error "My task failed"
    return 1
fi
```

### Adding New Commands

**1. Add Command Handler:**
```bash
# In cli/tfgrid-compose
case "$COMMAND" in
    my-command)
        # Implementation
        ;;
esac
```

**2. Update Help Text:**
```bash
# In core/common.sh show_help()
echo "  my-command <args>  - Description"
```

---

## Design Decisions

### Why Bash?

**Pros:**
- ✅ Universal availability (every Unix system)
- ✅ Easy to understand and debug
- ✅ Transparent execution (no compilation)
- ✅ Excellent for orchestration
- ✅ Direct integration with CLI tools
- ✅ Minimal dependencies

**Cons:**
- ❌ Error handling can be tricky
- ❌ No type safety
- ❌ Testing is harder

**Mitigation:**
- Use `set -e` (exit on error)
- Extensive validation
- Logging at each step
- Test scripts provided

### Why Pattern-Based?

**Benefits:**
- Different use cases need different infrastructure
- Patterns encapsulate best practices
- Easy to add new patterns without modifying core
- Users can create custom patterns

**Alternatives Considered:**
- Single monolithic template (too rigid)
- Full config DSL (too complex)
- GUI builder (not CLI-friendly)

### Why OpenTofu Priority?

**Rationale:**
- Open source (Apache 2.0 license)
- Compatible with Terraform
- Community-driven development
- No license restrictions
- Same user experience

**Fallback:**
- Terraform still supported
- Auto-detection at runtime
- No breaking changes

### Why State in `.tfgrid-compose/`?

**Benefits:**
- Co-located with deployment
- Easy to find and inspect
- Git-ignored by default
- Self-contained

**Alternatives:**
- `~/.tfgrid/` (harder to track per-project)
- Database (added complexity)
- Cloud storage (requires connectivity)

---

## Performance Considerations

### Deployment Speed

**Typical Timeline:**
- Infrastructure (Terraform): 30-60 seconds
- Network setup (WireGuard): 5-10 seconds
- Wait for SSH: 30-90 seconds
- Platform config (Ansible): 60-120 seconds
- App deployment: 10-30 seconds

**Total: 2-5 minutes**

### Optimization Opportunities

**1. Parallel Execution:**
- Multiple Ansible hosts configured in parallel
- Background tasks where possible

**2. Caching:**
- Terraform state cached locally
- Ansible facts cached between runs

**3. Incremental Updates:**
- Only run changed playbooks
- Terraform plan before apply

### Resource Usage

**Local Machine:**
- Minimal CPU usage (mostly waiting)
- Small disk footprint (<50MB for state)
- Network: Depends on Terraform operations

**Remote VMs:**
- Configured per pattern requirements
- Single-VM: 2-8 CPU, 4-16GB RAM typical
- Gateway: 1-2 CPU per VM, 2-4GB RAM
- K3s: 2+ CPU per node, 4+GB RAM

---

## Security Considerations

### Mnemonic Security

**Storage:**
- File permissions: 600 (read/write owner only)
- Standard location: `~/.config/threefold/mnemonic`
- Warning if permissions are incorrect

**Best Practices:**
- Never commit to version control
- Use environment variable in CI/CD
- Rotate regularly

### SSH Key Management

**Default Behavior:**
- Uses system SSH keys (`~/.ssh/id_*.pub`)
- Injected into VMs during deployment
- No passwords (key-based auth only)

### WireGuard Security

**Private Keys:**
- Generated by Terraform provider
- Stored in Terraform state (encrypted at rest)
- Deployed to `/etc/wireguard/` with 600 permissions

**Network Isolation:**
- Private networks per deployment
- No default internet routing
- Explicit rules required for external access

---

## Troubleshooting Architecture

### Debug Mode

**Enable:**
```bash
tfgrid-compose --debug up <app>
```

**Effects:**
- Verbose logging (`set -x`)
- Keep temporary files
- Show all command output
- Network diagnostics

### Log Files

All logs saved to `.tfgrid-compose/`:
- `terraform-init.log`
- `terraform-plan.log`
- `terraform-apply.log`
- `ansible.log`
- `hook-*.log`

### State Inspection

**Check Deployment:**
```bash
cat .tfgrid-compose/state.yaml
```

**Check Terraform State:**
```bash
cd .tfgrid-compose/terraform
terraform show
```

**Check WireGuard:**
```bash
sudo wg show
```

---

## Future Architecture

### Planned Enhancements

**1. Multi-Deployment Support**
```
~/.tfgrid-compose/
├── deployments/
│   ├── abc123/  # Deployment 1
│   └── def456/  # Deployment 2
└── index.yaml   # Registry
```

**2. Plugin System**
```
~/.tfgrid/plugins/
└── my-plugin/
    ├── plugin.yaml
    └── hooks/
```

**3. Remote State**
```yaml
# tfgrid-compose.yaml
state:
  backend: s3
  config:
    bucket: my-tfgrid-state
```

---

## References

- [Pattern Contract](../patterns/PATTERN_CONTRACT.md)
- [Quick Start Guide](QUICKSTART.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [Versioning Policy](https://docs.tfgrid.studio/development/versioning-policy/)

---

**Document Status:** Active  
**Last Updated:** 2025-10-14  
**Next Review:** After 1.0.0 release
