terraform {
  required_providers {
    grid = {
      source = "threefoldtech/grid"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

# ==============================================================================
# VARIABLES
# ==============================================================================

variable "mnemonic" {
  type        = string
  sensitive   = true
  description = "ThreeFold mnemonic for authentication"
}

variable "SSH_KEY" {
  type        = string
  default     = null
  description = "SSH public key content (if null, will auto-detect from ~/.ssh/)"
}

variable "tfgrid_network" {
  type        = string
  default     = "main"
  description = "ThreeFold Grid network (main, test, dev)"
}

variable "ai_agent_node" {
  type        = number
  description = "Node ID for AI Agent VM"
}

variable "ai_agent_cpu" {
  type    = number
  default = 4
}

variable "ai_agent_mem" {
  type    = number
  default = 8192 # 8GB RAM
}

variable "ai_agent_disk" {
  type    = number
  default = 100 # 100GB storage
}

# ==============================================================================
# LOCALS
# ==============================================================================

locals {
  # Auto-detect SSH key from local machine
  ssh_key = var.SSH_KEY != null ? var.SSH_KEY : (
    fileexists(pathexpand("~/.ssh/id_ed25519.pub")) ?
    file(pathexpand("~/.ssh/id_ed25519.pub")) :
    file(pathexpand("~/.ssh/id_rsa.pub"))
  )
}

# ==============================================================================
# PROVIDER
# ==============================================================================

provider "grid" {
  mnemonic  = var.mnemonic
  network   = var.tfgrid_network
  relay_url = var.tfgrid_network == "main" ? "wss://relay.grid.tf" : "wss://relay.test.grid.tf"
}

# ==============================================================================
# RANDOM RESOURCES
# ==============================================================================

# Generate unique suffix for deployment names (8 chars)
resource "random_string" "deployment_id" {
  length  = 8
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "random_bytes" "mycelium_key" {
  length = 32
}

resource "random_bytes" "ai_agent_ip_seed" {
  length = 6
}

# ==============================================================================
# NETWORK
# ==============================================================================

resource "grid_network" "ai_agent_network" {
  name          = "net_${random_string.deployment_id.result}"
  nodes         = [var.ai_agent_node]
  ip_range      = "10.1.0.0/16"
  add_wg_access = true
  mycelium_keys = {
    tostring(var.ai_agent_node) = random_bytes.mycelium_key.hex
  }
}

# ==============================================================================
# AI AGENT VM
# ==============================================================================

resource "grid_deployment" "ai_agent" {
  node         = var.ai_agent_node
  network_name = grid_network.ai_agent_network.name

  vms {
    name             = "vm_${random_string.deployment_id.result}"
    flist            = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
    cpu              = var.ai_agent_cpu
    memory           = var.ai_agent_mem
    rootfs_size      = var.ai_agent_disk * 1024  # Convert GB to MB
    entrypoint       = "/sbin/zinit init"
    mycelium_ip_seed = random_bytes.ai_agent_ip_seed.hex
    env_vars = {
      SSH_KEY = local.ssh_key
    }
  }
}

# ==============================================================================
# OUTPUTS
# ==============================================================================

# ==============================================================================
# STANDARD OUTPUTS (Required by tfgrid-compose orchestrator)
# All patterns MUST provide these outputs with these exact names
# ==============================================================================

output "primary_ip" {
  value       = try(grid_deployment.ai_agent.vms[0].ip, "")
  description = "Primary IP address for SSH connection (WireGuard IP)"
}

output "primary_ip_type" {
  value       = "wireguard"
  description = "Type of primary IP (wireguard, public, or mycelium)"
}

output "deployment_name" {
  value       = grid_deployment.ai_agent.name
  description = "Name of the deployment"
}

output "node_ids" {
  value       = [var.ai_agent_node]
  description = "List of node IDs used in deployment"
}

# ==============================================================================
# OPTIONAL OUTPUTS (Pattern-specific)
# ==============================================================================

output "deployment_id" {
  value       = random_string.deployment_id.result
  description = "Unique deployment identifier (8 char random string)"
}

output "mycelium_ip" {
  value       = try(grid_deployment.ai_agent.vms[0].mycelium_ip, "")
  description = "Mycelium IPv6 address"
}

output "wireguard_config" {
  value       = grid_network.ai_agent_network.access_wg_config
  sensitive   = true
  description = "WireGuard configuration file content"
}

output "network_name" {
  value       = grid_network.ai_agent_network.name
  description = "Network name"
}

# Legacy outputs (for backward compatibility)
output "ai_agent_node_id" {
  value       = var.ai_agent_node
  description = "Node ID (legacy)"
}

output "ai_agent_wg_ip" {
  value       = try(grid_deployment.ai_agent.vms[0].ip, "")
  description = "WireGuard IP (legacy)"
}

output "ai_agent_mycelium_ip" {
  value       = try(grid_deployment.ai_agent.vms[0].mycelium_ip, "")
  description = "Mycelium IP (legacy)"
}

output "wg_config" {
  value       = grid_network.ai_agent_network.access_wg_config
  sensitive   = true
  description = "WireGuard config (legacy)"
}
