terraform {
  required_providers {
    grid = {
      source  = "threefoldtech/grid"
    }
  }
}

# Variables
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

variable "tfgrid_network" {
  type        = string
  default     = "main"
  description = "ThreeFold Grid network (main, test, dev)"
}

provider "grid" {
  mnemonic  = var.mnemonic
  network   = var.tfgrid_network
  relay_url = var.tfgrid_network == "main" ? "wss://relay.grid.tf" : "wss://relay.test.grid.tf"
}

# Generate unique mycelium keys/seeds for all nodes
locals {
  all_nodes = concat([var.gateway_node], var.internal_nodes)
}

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

# Mycelium-enabled network
resource "grid_network" "gateway_network" {
  name          = "gateway_net"
  nodes         = local.all_nodes
  ip_range      = "10.1.0.0/16"
  add_wg_access = true
  mycelium_keys = {
    for node in local.all_nodes : tostring(node) => random_bytes.mycelium_key[tostring(node)].hex
  }
}

# Gateway VM with public IPv4
resource "grid_deployment" "gateway" {
  node         = var.gateway_node
  network_name = grid_network.gateway_network.name

  vms {
    name             = "gateway_vm"
    flist            = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
    cpu              = var.gateway_cpu
    memory           = var.gateway_mem
    entrypoint       = "/sbin/zinit init"
    publicip         = true
    mycelium_ip_seed = random_bytes.gateway_ip_seed.hex

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

# Internal VMs without public IPv4
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
    mycelium_ip_seed = random_bytes.internal_ip_seed[each.key].hex

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

# Outputs
output "gateway_public_ip" {
  value       = grid_deployment.gateway.vms[0].computedip
  description = "Public IPv4 address of the gateway VM"
}

output "gateway_wireguard_ip" {
  value       = grid_deployment.gateway.vms[0].ip
  description = "WireGuard IP of the gateway VM"
}

output "internal_wireguard_ips" {
  value = {
    for key, dep in grid_deployment.internal_vms :
    key => dep.vms[0].ip
  }
  description = "WireGuard IPs of internal VMs"
}

output "wg_config" {
  value = grid_network.gateway_network.access_wg_config
}

output "mycelium_ips" {
  value = {
    gateway = grid_deployment.gateway.vms[0].mycelium_ip
    internal = {
      for key, dep in grid_deployment.internal_vms :
      key => dep.vms[0].mycelium_ip
    }
  }
}

output "gateway_mycelium_ip" {
  value       = grid_deployment.gateway.vms[0].mycelium_ip
  description = "Mycelium IP of the gateway VM"
}

output "internal_mycelium_ips" {
  value = {
    for key, dep in grid_deployment.internal_vms :
    key => dep.vms[0].mycelium_ip
  }
  description = "Mycelium IPs of internal VMs"
}

output "tfgrid_network" {
  value       = var.tfgrid_network
  description = "ThreeFold Grid network (main, test, dev)"
}