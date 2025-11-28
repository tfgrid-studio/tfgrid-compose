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

variable "network_mode" {
  type        = string
  default     = "wireguard-only"
  description = "Network exposure mode: wireguard-only, mycelium-only, both"
}

variable "vm_node" {
  type        = number
  description = "Node ID for VM deployment"
}

variable "vm_cpu" {
  type    = number
  default = 2
}

variable "vm_mem" {
  type    = number
  default = 4096 # 4GB RAM
}

variable "vm_disk" {
  type    = number
  default = 50 # 50GB storage
}

variable "vm_public_ipv4" {
  type        = bool
  default     = false
  description = "Whether the VM should get a public IPv4 address"
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

resource "random_bytes" "vm_ip_seed" {
  length = 6
}

# ==============================================================================
# NETWORK
# ==============================================================================

resource "grid_network" "vm_network" {
  name          = "net_${random_string.deployment_id.result}"
  nodes         = [var.vm_node]
  ip_range      = "10.1.0.0/16"
  add_wg_access = var.network_mode != "mycelium-only"
  mycelium_keys = {
    tostring(var.vm_node) = random_bytes.mycelium_key.hex
  }
}

# ==============================================================================
# VIRTUAL MACHINE
# ==============================================================================

resource "grid_deployment" "vm" {
  node         = var.vm_node
  network_name = grid_network.vm_network.name

  vms {
    name             = "vm_${random_string.deployment_id.result}"
    flist            = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
    cpu              = var.vm_cpu
    memory           = var.vm_mem
    rootfs_size      = var.vm_disk * 1024  # Convert GB to MB
    entrypoint       = "/sbin/zinit init"
    publicip         = var.vm_public_ipv4
    mycelium_ip_seed = random_bytes.vm_ip_seed.hex
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
  value = var.vm_public_ipv4 ? (
    try(grid_deployment.vm.vms[0].computedip, "")
  ) : (
    try(grid_deployment.vm.vms[0].ip, "")
  )
  description = "Primary IP address for SSH connection (public IPv4 when enabled, otherwise WireGuard IP)"
}

output "primary_ip_type" {
  value       = var.vm_public_ipv4 ? "public" : "wireguard"
  description = "Type of primary IP (wireguard, public, or mycelium)"
}

output "deployment_name" {
  value       = grid_deployment.vm.name
  description = "Name of the deployment"
}

output "node_ids" {
  value       = [var.vm_node]
  description = "List of node IDs used in deployment"
}

# ==============================================================================
# OPTIONAL OUTPUTS (Pattern-specific)
# ==============================================================================

output "deployment_id" {
  value       = random_string.deployment_id.result
  description = "Unique deployment identifier (8 char random string)"
}

output "public_ip" {
  value       = try(grid_deployment.vm.vms[0].computedip, "")
  description = "Public IPv4 address of the VM (if enabled)"
}

output "wireguard_ip" {
  value       = try(grid_deployment.vm.vms[0].ip, "")
  description = "WireGuard IP of the VM"
}

output "mycelium_ip" {
  value       = try(grid_deployment.vm.vms[0].mycelium_ip, "")
  description = "Mycelium IPv6 address"
}

output "wg_config" {
  value       = grid_network.vm_network.access_wg_config
  sensitive   = true
  description = "WireGuard configuration file content"
}

output "network_name" {
  value       = grid_network.vm_network.name
  description = "Network name"
}
