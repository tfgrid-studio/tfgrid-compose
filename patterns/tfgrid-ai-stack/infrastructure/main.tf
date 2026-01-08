# TFGrid AI Stack - Terraform Infrastructure
# Version: 0.13.0

terraform {
  required_version = ">= 1.0"
  required_providers {
    grid = {
      source  = "threefoldtech/grid"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# ==============================================================================
# LOCALS
# ==============================================================================

locals {
  # Handle legacy variables for backward compatibility
  use_legacy = var.network_mode != ""

  legacy_mycelium = (
    var.network_mode == "mycelium-only" ||
    var.network_mode == "both"
  )
  legacy_wireguard = (
    var.network_mode == "wireguard-only" ||
    var.network_mode == "both"
  )

  # Final provisioning decisions
  enable_mycelium  = local.use_legacy ? local.legacy_mycelium : var.provision_mycelium
  enable_wireguard = local.use_legacy ? local.legacy_wireguard : var.provision_wireguard
  enable_ipv4      = var.provision_ipv4 || (var.domain != "")
  enable_ipv6      = var.provision_ipv6

  # All nodes for network
  all_nodes = compact([
    var.gateway_node_id,
    var.ai_agent_node_id,
    var.gitea_node_id
  ])

  ssh_key = var.ssh_key != "" ? var.ssh_key : (
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

resource "random_password" "gateway_api_key" {
  length  = 32
  special = true
}

resource "random_password" "gitea_admin_password" {
  length  = 16
  special = true
}

resource "random_password" "gitea_db_password" {
  length  = 24
  special = true
}

resource "random_string" "deployment_id" {
  length  = 8
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "random_bytes" "mycelium_key" {
  for_each = toset([for n in local.all_nodes : tostring(n) if n != 0])
  length   = 32
}

resource "random_bytes" "gateway_ip_seed" {
  length = 6
}

resource "random_bytes" "ai_agent_ip_seed" {
  length = 6
}

resource "random_bytes" "gitea_ip_seed" {
  length = 6
}

# ==============================================================================
# NETWORK
# ==============================================================================

resource "grid_network" "ai_stack_network" {
  name          = "ai_stack_net_${random_string.deployment_id.result}"
  nodes         = local.all_nodes
  ip_range      = "10.1.0.0/16"
  add_wg_access = local.enable_wireguard

  mycelium_keys = local.enable_mycelium ? {
    for node in local.all_nodes : tostring(node) => random_bytes.mycelium_key[tostring(node)].hex if node != 0
  } : {}
}

# ==============================================================================
# GATEWAY VM - Nginx + Route API + Monitoring
# ==============================================================================

resource "grid_deployment" "gateway" {
  node         = var.gateway_node_id
  network_name = grid_network.ai_stack_network.name

  vms {
    name             = "gateway_${random_string.deployment_id.result}"
    flist            = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
    cpu              = var.gateway_cpu
    memory           = var.gateway_memory
    rootfs_size      = var.gateway_disk
    entrypoint       = "/sbin/zinit init"
    publicip         = local.enable_ipv4
    publicip6        = local.enable_ipv6
    mycelium_ip_seed = local.enable_mycelium ? random_bytes.gateway_ip_seed.hex : ""

    env_vars = {
      SSH_KEY    = local.ssh_key
      DOMAIN     = var.domain
      SSL_EMAIL  = var.ssl_email
      API_KEY    = random_password.gateway_api_key.result
    }
  }
}

# ==============================================================================
# AI AGENT VM - qwen-cli + Project Management
# ==============================================================================

resource "grid_deployment" "ai_agent" {
  node         = var.ai_agent_node_id
  network_name = grid_network.ai_stack_network.name

  vms {
    name             = "ai_agent_${random_string.deployment_id.result}"
    flist            = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
    cpu              = var.ai_agent_cpu
    memory           = var.ai_agent_memory
    rootfs_size      = var.ai_agent_disk
    entrypoint       = "/sbin/zinit init"
    publicip         = false
    mycelium_ip_seed = local.enable_mycelium ? random_bytes.ai_agent_ip_seed.hex : ""

    env_vars = {
      SSH_KEY         = local.ssh_key
      GATEWAY_IP      = local.enable_mycelium ? grid_deployment.gateway.vms[0].mycelium_ip : grid_deployment.gateway.vms[0].ip
      GATEWAY_API_KEY = random_password.gateway_api_key.result
      GITEA_IP        = local.enable_mycelium ? grid_deployment.gitea.vms[0].mycelium_ip : grid_deployment.gitea.vms[0].ip
    }
  }

  depends_on = [grid_deployment.gateway, grid_deployment.gitea]
}

# ==============================================================================
# GITEA VM - Git Hosting
# ==============================================================================

resource "grid_deployment" "gitea" {
  node         = var.gitea_node_id
  network_name = grid_network.ai_stack_network.name

  vms {
    name             = "gitea_${random_string.deployment_id.result}"
    flist            = "https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist"
    cpu              = var.gitea_cpu
    memory           = var.gitea_memory
    rootfs_size      = var.gitea_disk
    entrypoint       = "/sbin/zinit init"
    publicip         = false
    mycelium_ip_seed = local.enable_mycelium ? random_bytes.gitea_ip_seed.hex : ""

    env_vars = {
      SSH_KEY              = local.ssh_key
      GITEA_ADMIN_USER     = var.gitea_admin_user
      GITEA_ADMIN_PASSWORD = random_password.gitea_admin_password.result
      GITEA_ADMIN_EMAIL    = var.gitea_admin_email
      GITEA_DB_PASSWORD    = random_password.gitea_db_password.result
    }
  }
}

# ==============================================================================
# LOCAL FILES
# ==============================================================================

resource "local_file" "ssh_config" {
  filename = "${path.module}/../.ssh_config"
  content = <<-EOT
    # TFGrid AI Stack SSH Configuration
    # Generated by Terraform

    Host gateway
      HostName ${local.enable_mycelium ? grid_deployment.gateway.vms[0].mycelium_ip : grid_deployment.gateway.vms[0].ip}
      User root
      IdentityFile ${var.ssh_key_path}
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null

    Host ai-agent
      HostName ${local.enable_mycelium ? grid_deployment.ai_agent.vms[0].mycelium_ip : grid_deployment.ai_agent.vms[0].ip}
      User root
      IdentityFile ${var.ssh_key_path}
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null

    Host gitea
      HostName ${local.enable_mycelium ? grid_deployment.gitea.vms[0].mycelium_ip : grid_deployment.gitea.vms[0].ip}
      User root
      IdentityFile ${var.ssh_key_path}
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
  EOT

  file_permission = "0600"
}

resource "local_sensitive_file" "credentials" {
  filename = "${path.module}/../.credentials"
  content = <<-EOT
    # TFGrid AI Stack Credentials
    # KEEP THIS FILE SECURE!

    GATEWAY_API_KEY=${random_password.gateway_api_key.result}
    GITEA_ADMIN_USER=${var.gitea_admin_user}
    GITEA_ADMIN_PASSWORD=${random_password.gitea_admin_password.result}
    GITEA_DB_PASSWORD=${random_password.gitea_db_password.result}

    # Access URLs
    GATEWAY_IP=${local.enable_mycelium ? grid_deployment.gateway.vms[0].mycelium_ip : grid_deployment.gateway.vms[0].ip}
    ${var.domain != "" ? "GATEWAY_PUBLIC_URL=https://${var.domain}" : ""}
    AI_AGENT_IP=${local.enable_mycelium ? grid_deployment.ai_agent.vms[0].mycelium_ip : grid_deployment.ai_agent.vms[0].ip}
    GITEA_IP=${local.enable_mycelium ? grid_deployment.gitea.vms[0].mycelium_ip : grid_deployment.gitea.vms[0].ip}
  EOT

  file_permission = "0600"
}
