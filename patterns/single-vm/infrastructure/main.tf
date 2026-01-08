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

# ------------------------------------------------------------------------------
# Network Provisioning Variables
# At least one must be true
# ------------------------------------------------------------------------------

variable "provision_mycelium" {
  type        = bool
  default     = true
  description = "Provision Mycelium overlay network (IPv6, encrypted, recommended)"
}

variable "provision_wireguard" {
  type        = bool
  default     = false
  description = "Provision WireGuard VPN access (private network, encrypted)"
}

variable "provision_ipv4" {
  type        = bool
  default     = false
  description = "Provision public IPv4 address"
}

variable "provision_ipv6" {
  type        = bool
  default     = false
  description = "Provision public IPv6 address"
}

# Legacy variable for backward compatibility
variable "network_mode" {
  type        = string
  default     = ""
  description = "DEPRECATED: Use provision_* variables instead. Kept for backward compatibility."
}

# Legacy variable for backward compatibility
variable "vm_public_ipv4" {
  type        = bool
  default     = false
  description = "DEPRECATED: Use provision_ipv4 instead. Kept for backward compatibility."
}

# ------------------------------------------------------------------------------
# VM Resource Variables
# ------------------------------------------------------------------------------

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

  # Handle legacy network_mode variable for backward compatibility
  # Convert old format to new provision_* format
  legacy_mycelium = (
    var.network_mode == "mycelium-only" ||
    var.network_mode == "both" ||
    var.network_mode == "mycelium,ipv4" ||
    var.network_mode == "mycelium,wireguard"
  )
  legacy_wireguard = (
    var.network_mode == "wireguard-only" ||
    var.network_mode == "both" ||
    var.network_mode == "mycelium,wireguard"
  )

  # Final provisioning decisions (new vars take precedence, then legacy, then defaults)
  # If network_mode is set (legacy), use legacy logic; otherwise use new provision_* vars
  use_legacy = var.network_mode != ""

  enable_mycelium  = local.use_legacy ? local.legacy_mycelium : var.provision_mycelium
  enable_wireguard = local.use_legacy ? local.legacy_wireguard : var.provision_wireguard
  enable_ipv4      = var.vm_public_ipv4 || var.provision_ipv4
  enable_ipv6      = var.provision_ipv6
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
  add_wg_access = local.enable_wireguard

  # Only configure mycelium keys if mycelium is enabled
  mycelium_keys = local.enable_mycelium ? {
    tostring(var.vm_node) = random_bytes.mycelium_key.hex
  } : {}
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
    publicip         = local.enable_ipv4
    publicip6        = local.enable_ipv6
    mycelium_ip_seed = local.enable_mycelium ? random_bytes.vm_ip_seed.hex : ""
    env_vars = {
      SSH_KEY = local.ssh_key
    }
  }
}

# ==============================================================================
# OUTPUTS - All Available Network Addresses
# ==============================================================================

output "mycelium_ip" {
  value       = local.enable_mycelium ? try(grid_deployment.vm.vms[0].mycelium_ip, "") : ""
  description = "Mycelium IPv6 address (if provisioned)"
}

output "wireguard_ip" {
  value       = local.enable_wireguard ? try(grid_deployment.vm.vms[0].ip, "") : ""
  description = "WireGuard private IP address (if provisioned)"
}

output "ipv4_address" {
  value       = local.enable_ipv4 ? try(grid_deployment.vm.vms[0].computedip, "") : ""
  description = "Public IPv4 address (if provisioned)"
}

output "ipv6_address" {
  value       = local.enable_ipv6 ? try(grid_deployment.vm.vms[0].computedip6, "") : ""
  description = "Public IPv6 address (if provisioned)"
}

# WireGuard config (needed to set up local WireGuard interface)
output "wg_config" {
  value       = local.enable_wireguard ? grid_network.vm_network.access_wg_config : ""
  sensitive   = true
  description = "WireGuard configuration file content (if provisioned)"
}

# ==============================================================================
# OUTPUTS - Provisioning Status
# ==============================================================================

output "provisioned_networks" {
  value = join(",", compact([
    local.enable_mycelium ? "mycelium" : "",
    local.enable_wireguard ? "wireguard" : "",
    local.enable_ipv4 ? "ipv4" : "",
    local.enable_ipv6 ? "ipv6" : ""
  ]))
  description = "Comma-separated list of provisioned networks"
}

# ==============================================================================
# OUTPUTS - Deployment Metadata
# ==============================================================================

output "deployment_id" {
  value       = random_string.deployment_id.result
  description = "Unique deployment identifier (8 char random string)"
}

output "deployment_name" {
  value       = grid_deployment.vm.name
  description = "Name of the deployment"
}

output "node_ids" {
  value       = [var.vm_node]
  description = "List of node IDs used in deployment"
}

output "network_name" {
  value       = grid_network.vm_network.name
  description = "Network name"
}

# ==============================================================================
# LEGACY OUTPUTS - For backward compatibility
# These will be removed in a future version
# ==============================================================================

output "primary_ip" {
  value = (
    local.enable_ipv4 ? try(grid_deployment.vm.vms[0].computedip, "") :
    local.enable_mycelium ? try(grid_deployment.vm.vms[0].mycelium_ip, "") :
    local.enable_wireguard ? try(grid_deployment.vm.vms[0].ip, "") :
    local.enable_ipv6 ? try(grid_deployment.vm.vms[0].computedip6, "") :
    ""
  )
  description = "DEPRECATED: Use specific IP outputs and prefer logic instead. Primary IP for legacy compatibility."
}

output "primary_ip_type" {
  value = (
    local.enable_ipv4 ? "ipv4" :
    local.enable_mycelium ? "mycelium" :
    local.enable_wireguard ? "wireguard" :
    local.enable_ipv6 ? "ipv6" :
    ""
  )
  description = "DEPRECATED: Use provisioned_networks instead. Type of primary IP for legacy compatibility."
}

output "public_ip" {
  value       = try(grid_deployment.vm.vms[0].computedip, "")
  description = "DEPRECATED: Use ipv4_address instead."
}
