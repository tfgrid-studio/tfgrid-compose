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
  description = "SSH public key content (if null, will use ~/.ssh/id_ed25519.pub)"
}

variable "tfgrid_network" {
  type        = string
  default     = "main"
  description = "ThreeFold Grid network (main or test)"
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
  description = "Provision public IPv4 address for worker nodes"
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

variable "worker_public_ipv4" {
  type        = bool
  default     = false
  description = "DEPRECATED: Use provision_ipv4 instead."
}

# ------------------------------------------------------------------------------
# Node Configuration
# ------------------------------------------------------------------------------

variable "control_nodes" { type = list(number) }
variable "worker_nodes" { type = list(number) }
variable "ingress_nodes" {
  type        = list(number)
  default     = []
  description = "Node IDs for dedicated ingress nodes (optional)"
}
variable "management_node" { type = number }

variable "control_cpu" { type = number }
variable "control_mem" { type = number }
variable "control_disk" { type = number }
variable "worker_cpu" { type = number }
variable "worker_mem" { type = number }
variable "worker_disk" { type = number }

variable "ingress_cpu" {
  type    = number
  default = 2
}
variable "ingress_mem" {
  type    = number
  default = 4096
}
variable "ingress_disk" {
  type    = number
  default = 25
}

variable "management_cpu" {
  type    = number
  default = 1
}
variable "management_mem" {
  type    = number
  default = 2048
}
variable "management_disk" {
  type    = number
  default = 25
}

variable "network_name" {
  type        = string
  default     = "k3s_cluster_net"
  description = "Name of the network for the cluster"
}

# ==============================================================================
# LOCALS
# ==============================================================================

locals {
  cluster_nodes     = concat(var.control_nodes, var.worker_nodes)
  ingress_nodes     = var.ingress_nodes
  all_cluster_nodes = concat(local.cluster_nodes, local.ingress_nodes)
  all_nodes         = concat([var.management_node], local.all_cluster_nodes)
  has_ingress_nodes = length(var.ingress_nodes) > 0

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
  enable_ipv4      = var.worker_public_ipv4 || var.provision_ipv4
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

resource "random_bytes" "k3s_mycelium_key" {
  for_each = toset([for n in local.all_cluster_nodes : tostring(n)])
  length   = 32
}

resource "random_bytes" "k3s_ip_seed" {
  for_each = toset([for n in local.all_cluster_nodes : tostring(n)])
  length   = 6
}

resource "random_bytes" "mgmt_mycelium_key" {
  length = 32
}

resource "random_bytes" "mgmt_ip_seed" {
  length = 6
}

# ==============================================================================
# NETWORK
# ==============================================================================

resource "grid_network" "k3s_network" {
  name          = var.network_name
  nodes         = local.all_nodes
  ip_range      = "10.1.0.0/16"
  add_wg_access = local.enable_wireguard

  mycelium_keys = local.enable_mycelium ? merge(
    {
      for node in local.all_cluster_nodes : tostring(node) => random_bytes.k3s_mycelium_key[tostring(node)].hex
    },
    {
      tostring(var.management_node) = random_bytes.mgmt_mycelium_key.hex
    }
  ) : {}
}

# ==============================================================================
# CLUSTER NODES
# ==============================================================================

resource "grid_deployment" "k3s_nodes" {
  for_each = {
    for idx, node in local.cluster_nodes :
    "node_${idx}" => {
      node_id    = node
      is_control = contains(var.control_nodes, node)
    }
  }

  node         = each.value.node_id
  network_name = grid_network.k3s_network.name

  disks {
    name = "disk_${each.key}"
    size = each.value.is_control ? var.control_disk : var.worker_disk
  }

  vms {
    name             = "vm_${each.key}"
    flist            = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
    cpu              = each.value.is_control ? var.control_cpu : var.worker_cpu
    memory           = each.value.is_control ? var.control_mem : var.worker_mem
    entrypoint       = "/sbin/zinit init"
    publicip         = !each.value.is_control && local.enable_ipv4
    publicip6        = !each.value.is_control && local.enable_ipv6
    mycelium_ip_seed = local.enable_mycelium ? random_bytes.k3s_ip_seed[tostring(each.value.node_id)].hex : ""

    env_vars = {
      SSH_KEY = var.SSH_KEY != null ? var.SSH_KEY : (
        fileexists(pathexpand("~/.ssh/id_ed25519.pub")) ?
        file(pathexpand("~/.ssh/id_ed25519.pub")) :
        file(pathexpand("~/.ssh/id_rsa.pub"))
      )
    }

    mounts {
      name        = "disk_${each.key}"
      mount_point = "/data"
    }
    rootfs_size = 20480
  }
}

# ==============================================================================
# INGRESS NODES (Optional)
# ==============================================================================

resource "grid_deployment" "ingress_nodes" {
  for_each = {
    for idx, node in local.ingress_nodes :
    "ingress_${idx}" => {
      node_id = node
    }
  }

  node         = each.value.node_id
  network_name = grid_network.k3s_network.name

  disks {
    name = "disk_${each.key}"
    size = var.ingress_disk
  }

  vms {
    name             = "vm_${each.key}"
    flist            = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
    cpu              = var.ingress_cpu
    memory           = var.ingress_mem
    entrypoint       = "/sbin/zinit init"
    publicip         = true  # Ingress nodes always get public IPs
    publicip6        = local.enable_ipv6
    mycelium_ip_seed = local.enable_mycelium ? random_bytes.k3s_ip_seed[tostring(each.value.node_id)].hex : ""

    env_vars = {
      SSH_KEY = var.SSH_KEY != null ? var.SSH_KEY : (
        fileexists(pathexpand("~/.ssh/id_ed25519.pub")) ?
        file(pathexpand("~/.ssh/id_ed25519.pub")) :
        file(pathexpand("~/.ssh/id_rsa.pub"))
      )
    }

    mounts {
      name        = "disk_${each.key}"
      mount_point = "/data"
    }
    rootfs_size = 10240
  }
}

# ==============================================================================
# MANAGEMENT NODE
# ==============================================================================

resource "grid_deployment" "management_node" {
  node         = var.management_node
  network_name = grid_network.k3s_network.name

  disks {
    name = "disk_mgmt"
    size = var.management_disk
  }

  vms {
    name             = "vm_management"
    flist            = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
    cpu              = var.management_cpu
    memory           = var.management_mem
    entrypoint       = "/sbin/zinit init"
    publicip         = false
    mycelium_ip_seed = local.enable_mycelium ? random_bytes.mgmt_ip_seed.hex : ""

    env_vars = {
      SSH_KEY = var.SSH_KEY != null ? var.SSH_KEY : (
        fileexists(pathexpand("~/.ssh/id_ed25519.pub")) ?
        file(pathexpand("~/.ssh/id_ed25519.pub")) :
        file(pathexpand("~/.ssh/id_rsa.pub"))
      )
    }

    mounts {
      name        = "disk_mgmt"
      mount_point = "/data"
    }
    rootfs_size = 10240
  }
}

# ==============================================================================
# OUTPUTS - Management Node Network Addresses
# ==============================================================================

output "mycelium_ip" {
  value       = local.enable_mycelium ? try(grid_deployment.management_node.vms[0].mycelium_ip, "") : ""
  description = "Management node Mycelium IPv6 address (if provisioned)"
}

output "wireguard_ip" {
  value       = local.enable_wireguard ? try(grid_deployment.management_node.vms[0].ip, "") : ""
  description = "Management node WireGuard private IP address (if provisioned)"
}

output "ipv4_address" {
  value       = ""
  description = "Management node does not have public IPv4"
}

output "ipv6_address" {
  value       = ""
  description = "Management node does not have public IPv6"
}

output "wg_config" {
  value       = local.enable_wireguard ? grid_network.k3s_network.access_wg_config : ""
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
# OUTPUTS - Cluster Node IPs
# ==============================================================================

output "cluster_mycelium_ips" {
  value = local.enable_mycelium ? {
    for key, dep in grid_deployment.k3s_nodes :
    key => dep.vms[0].mycelium_ip
  } : {}
  description = "Mycelium IPs of cluster nodes"
}

output "cluster_wireguard_ips" {
  value = local.enable_wireguard ? {
    for key, dep in grid_deployment.k3s_nodes :
    key => dep.vms[0].ip
  } : {}
  description = "WireGuard IPs of cluster nodes"
}

output "cluster_ipv4_addresses" {
  value = local.enable_ipv4 ? {
    for key, dep in grid_deployment.k3s_nodes :
    key => dep.vms[0].computedip if contains(var.worker_nodes, dep.node)
  } : {}
  description = "Public IPv4 addresses of worker nodes"
}

output "ingress_mycelium_ips" {
  value = local.enable_mycelium ? {
    for key, dep in grid_deployment.ingress_nodes :
    key => dep.vms[0].mycelium_ip
  } : {}
  description = "Mycelium IPs of ingress nodes"
}

output "ingress_wireguard_ips" {
  value = local.enable_wireguard ? {
    for key, dep in grid_deployment.ingress_nodes :
    key => dep.vms[0].ip
  } : {}
  description = "WireGuard IPs of ingress nodes"
}

output "ingress_ipv4_addresses" {
  value = {
    for key, dep in grid_deployment.ingress_nodes :
    key => dep.vms[0].computedip
  }
  description = "Public IPv4 addresses of ingress nodes (for DNS A records)"
}

output "has_ingress_nodes" {
  value       = local.has_ingress_nodes
  description = "Whether dedicated ingress nodes are configured"
}

# ==============================================================================
# OUTPUTS - Deployment Metadata
# ==============================================================================

output "deployment_name" {
  value       = "k3s_cluster"
  description = "Name of the deployment"
}

output "node_ids" {
  value       = local.all_nodes
  description = "List of all node IDs used in deployment"
}

output "connection_info" {
  value = {
    method     = "kubectl"
    endpoint   = local.enable_wireguard ? "https://${grid_deployment.k3s_nodes["node_0"].vms[0].ip}:6443" : ""
    management = local.enable_mycelium ? grid_deployment.management_node.vms[0].mycelium_ip : grid_deployment.management_node.vms[0].ip
  }
  description = "K3s cluster connection information"
}

# ==============================================================================
# LEGACY OUTPUTS - For backward compatibility
# ==============================================================================

output "wireguard_ips" {
  value = {
    for key, dep in grid_deployment.k3s_nodes :
    key => dep.vms[0].ip
  }
  description = "DEPRECATED: Use cluster_wireguard_ips instead."
}

output "mycelium_ips" {
  value = {
    for key, dep in grid_deployment.k3s_nodes :
    key => dep.vms[0].mycelium_ip
  }
  description = "DEPRECATED: Use cluster_mycelium_ips instead."
}

output "worker_public_ips" {
  value = {
    for key, dep in grid_deployment.k3s_nodes :
    key => dep.vms[0].computedip if contains(var.worker_nodes, dep.node)
  }
  description = "DEPRECATED: Use cluster_ipv4_addresses instead."
}

output "management_mycelium_ip" {
  value       = try(grid_deployment.management_node.vms[0].mycelium_ip, "")
  description = "DEPRECATED: Use mycelium_ip instead."
}

output "management_node_wireguard_ip" {
  value       = try(grid_deployment.management_node.vms[0].ip, "")
  description = "DEPRECATED: Use wireguard_ip instead."
}

output "primary_ip" {
  value = (
    local.enable_mycelium ? try(grid_deployment.management_node.vms[0].mycelium_ip, "") :
    local.enable_wireguard ? try(grid_deployment.management_node.vms[0].ip, "") :
    ""
  )
  description = "DEPRECATED: Use mycelium_ip or wireguard_ip instead."
}

output "primary_ip_type" {
  value = (
    local.enable_mycelium ? "mycelium" :
    local.enable_wireguard ? "wireguard" :
    ""
  )
  description = "DEPRECATED: Use provisioned_networks instead."
}

output "secondary_ips" {
  value = concat(
    [
      for key, dep in grid_deployment.k3s_nodes : {
        name = "cluster_node_${key}"
        ip   = dep.vms[0].ip
        type = "wireguard"
        role = contains(var.control_nodes, dep.node) ? "control" : "worker"
      }
    ],
    [
      for key, dep in grid_deployment.ingress_nodes : {
        name      = "ingress_node_${key}"
        ip        = dep.vms[0].ip
        type      = "wireguard"
        role      = "ingress"
        public_ip = dep.vms[0].computedip
      }
    ]
  )
  description = "DEPRECATED: Use cluster_wireguard_ips/ingress_wireguard_ips instead."
}
