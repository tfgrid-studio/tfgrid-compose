terraform {
  required_providers {
    grid = {
      source  = "threefoldtech/grid"
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
  description = "SSH public key content (if null, will use ~/.ssh/id_ed25519.pub)"
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
  description = "Provision public IPv4 address for gateway"
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

variable "main_network" {
  type        = string
  default     = ""
  description = "DEPRECATED: Use provision_* variables instead."
}

# ------------------------------------------------------------------------------
# Node Configuration
# ------------------------------------------------------------------------------

variable "gateway_node" { type = number }
variable "internal_nodes" { type = list(number) }

variable "gateway_cpu" {
  type    = number
  default = 2
}
variable "gateway_mem" {
  type    = number
  default = 4096 # 4GB RAM
}
variable "gateway_disk" {
  type    = number
  default = 50 # 50GB storage
}

variable "internal_cpu" {
  type    = number
  default = 2
}
variable "internal_mem" {
  type    = number
  default = 2048 # 2GB RAM
}
variable "internal_disk" {
  type    = number
  default = 25 # 25GB storage
}

# ==============================================================================
# LOCALS
# ==============================================================================

locals {
  all_nodes = concat([var.gateway_node], var.internal_nodes)

  # Handle legacy network_mode variable for backward compatibility
  legacy_mycelium = (
    var.network_mode == "mycelium-only" ||
    var.network_mode == "both"
  )
  legacy_wireguard = (
    var.network_mode == "wireguard-only" ||
    var.network_mode == "both"
  )

  # Final provisioning decisions
  use_legacy = var.network_mode != ""

  enable_mycelium  = local.use_legacy ? local.legacy_mycelium : var.provision_mycelium
  enable_wireguard = local.use_legacy ? local.legacy_wireguard : var.provision_wireguard
  enable_ipv4      = var.provision_ipv4
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

resource "random_bytes" "mycelium_key" {
  for_each = toset([for n in local.all_nodes : tostring(n)])
  length   = 32
}

resource "random_bytes" "gateway_ip_seed" {
  length = 6
}

resource "random_bytes" "internal_ip_seed" {
  for_each = toset([for n in var.internal_nodes : tostring(n)])
  length   = 6
}

# ==============================================================================
# NETWORK
# ==============================================================================

resource "grid_network" "gateway_network" {
  name          = "gateway_net"
  nodes         = local.all_nodes
  ip_range      = "10.1.0.0/16"
  add_wg_access = local.enable_wireguard

  mycelium_keys = local.enable_mycelium ? {
    for node in local.all_nodes : tostring(node) => random_bytes.mycelium_key[tostring(node)].hex
  } : {}
}

# ==============================================================================
# GATEWAY VM - with public IP
# ==============================================================================

resource "grid_deployment" "gateway" {
  node         = var.gateway_node
  network_name = grid_network.gateway_network.name

  vms {
    name             = "gateway_vm"
    flist            = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
    cpu              = var.gateway_cpu
    memory           = var.gateway_mem
    entrypoint       = "/sbin/zinit init"
    publicip         = local.enable_ipv4
    publicip6        = local.enable_ipv6
    mycelium_ip_seed = local.enable_mycelium ? random_bytes.gateway_ip_seed.hex : ""

    env_vars = {
      SSH_KEY = var.SSH_KEY != null ? var.SSH_KEY : (
        fileexists(pathexpand("~/.ssh/id_ed25519.pub")) ?
        file(pathexpand("~/.ssh/id_ed25519.pub")) :
        file(pathexpand("~/.ssh/id_rsa.pub"))
      )
    }
    rootfs_size = 20480
  }
}

# ==============================================================================
# INTERNAL VMs - without public IP
# ==============================================================================

resource "grid_deployment" "internal_vms" {
  for_each = toset([for n in var.internal_nodes : tostring(n)])

  node         = each.value
  network_name = grid_network.gateway_network.name

  vms {
    name             = "internal_vm_${each.key}"
    flist            = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
    cpu              = var.internal_cpu
    memory           = var.internal_mem
    entrypoint       = "/sbin/zinit init"
    publicip         = false
    mycelium_ip_seed = local.enable_mycelium ? random_bytes.internal_ip_seed[each.key].hex : ""

    env_vars = {
      SSH_KEY = var.SSH_KEY != null ? var.SSH_KEY : (
        fileexists(pathexpand("~/.ssh/id_ed25519.pub")) ?
        file(pathexpand("~/.ssh/id_ed25519.pub")) :
        file(pathexpand("~/.ssh/id_rsa.pub"))
      )
    }
    rootfs_size = 10240
  }
}

# ==============================================================================
# OUTPUTS - All Available Network Addresses (Gateway)
# ==============================================================================

output "mycelium_ip" {
  value       = local.enable_mycelium ? try(grid_deployment.gateway.vms[0].mycelium_ip, "") : ""
  description = "Gateway Mycelium IPv6 address (if provisioned)"
}

output "wireguard_ip" {
  value       = local.enable_wireguard ? try(grid_deployment.gateway.vms[0].ip, "") : ""
  description = "Gateway WireGuard private IP address (if provisioned)"
}

output "ipv4_address" {
  value       = local.enable_ipv4 ? try(grid_deployment.gateway.vms[0].computedip, "") : ""
  description = "Gateway public IPv4 address (if provisioned)"
}

output "ipv6_address" {
  value       = local.enable_ipv6 ? try(grid_deployment.gateway.vms[0].computedip6, "") : ""
  description = "Gateway public IPv6 address (if provisioned)"
}

output "wg_config" {
  value       = local.enable_wireguard ? grid_network.gateway_network.access_wg_config : ""
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
# OUTPUTS - Internal VMs
# ==============================================================================

output "internal_mycelium_ips" {
  value = local.enable_mycelium ? {
    for key, dep in grid_deployment.internal_vms :
    key => dep.vms[0].mycelium_ip
  } : {}
  description = "Mycelium IPs of internal VMs"
}

output "internal_wireguard_ips" {
  value = local.enable_wireguard ? {
    for key, dep in grid_deployment.internal_vms :
    key => dep.vms[0].ip
  } : {}
  description = "WireGuard IPs of internal VMs"
}

# ==============================================================================
# OUTPUTS - Deployment Metadata
# ==============================================================================

output "deployment_name" {
  value       = "gateway_deployment"
  description = "Name of the deployment"
}

output "node_ids" {
  value       = concat([var.gateway_node], var.internal_nodes)
  description = "List of all node IDs used in deployment"
}

# ==============================================================================
# LEGACY OUTPUTS - For backward compatibility
# ==============================================================================

output "gateway_public_ip" {
  value       = try(grid_deployment.gateway.vms[0].computedip, "")
  description = "DEPRECATED: Use ipv4_address instead."
}

output "gateway_wireguard_ip" {
  value       = try(grid_deployment.gateway.vms[0].ip, "")
  description = "DEPRECATED: Use wireguard_ip instead."
}

output "gateway_mycelium_ip" {
  value       = try(grid_deployment.gateway.vms[0].mycelium_ip, "")
  description = "DEPRECATED: Use mycelium_ip instead."
}

output "mycelium_ips" {
  value = {
    gateway = try(grid_deployment.gateway.vms[0].mycelium_ip, "")
    internal = {
      for key, dep in grid_deployment.internal_vms :
      key => dep.vms[0].mycelium_ip
    }
  }
  description = "DEPRECATED: Use mycelium_ip and internal_mycelium_ips instead."
}

output "primary_ip" {
  value = (
    local.enable_ipv4 ? try(grid_deployment.gateway.vms[0].computedip, "") :
    local.enable_mycelium ? try(grid_deployment.gateway.vms[0].mycelium_ip, "") :
    local.enable_wireguard ? try(grid_deployment.gateway.vms[0].ip, "") :
    ""
  )
  description = "DEPRECATED: Use specific IP outputs instead."
}

output "primary_ip_type" {
  value = (
    local.enable_ipv4 ? "ipv4" :
    local.enable_mycelium ? "mycelium" :
    local.enable_wireguard ? "wireguard" :
    ""
  )
  description = "DEPRECATED: Use provisioned_networks instead."
}

output "secondary_ips" {
  value = [
    for key, dep in grid_deployment.internal_vms : {
      name = "internal_vm_${key}"
      ip   = dep.vms[0].ip
      type = "wireguard"
      role = "backend"
    }
  ]
  description = "DEPRECATED: Use internal_wireguard_ips/internal_mycelium_ips instead."
}
