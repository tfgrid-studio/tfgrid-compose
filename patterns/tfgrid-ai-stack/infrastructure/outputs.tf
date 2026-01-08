# TFGrid AI Stack - Terraform Outputs
# Version: 0.13.0

# ==============================================================================
# OUTPUTS - Gateway Network Addresses
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
  value       = local.enable_wireguard ? grid_network.ai_stack_network.access_wg_config : ""
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
# OUTPUTS - Component VM IPs
# ==============================================================================

output "gateway_mycelium_ip" {
  value       = local.enable_mycelium ? try(grid_deployment.gateway.vms[0].mycelium_ip, "") : ""
  description = "Gateway Mycelium IP"
}

output "gateway_wireguard_ip" {
  value       = local.enable_wireguard ? try(grid_deployment.gateway.vms[0].ip, "") : ""
  description = "Gateway WireGuard IP"
}

output "ai_agent_mycelium_ip" {
  value       = local.enable_mycelium ? try(grid_deployment.ai_agent.vms[0].mycelium_ip, "") : ""
  description = "AI Agent Mycelium IP"
}

output "ai_agent_wireguard_ip" {
  value       = local.enable_wireguard ? try(grid_deployment.ai_agent.vms[0].ip, "") : ""
  description = "AI Agent WireGuard IP"
}

output "gitea_mycelium_ip" {
  value       = local.enable_mycelium ? try(grid_deployment.gitea.vms[0].mycelium_ip, "") : ""
  description = "Gitea Mycelium IP"
}

output "gitea_wireguard_ip" {
  value       = local.enable_wireguard ? try(grid_deployment.gitea.vms[0].ip, "") : ""
  description = "Gitea WireGuard IP"
}

# ==============================================================================
# OUTPUTS - Deployment Metadata
# ==============================================================================

output "deployment_name" {
  description = "Name of the deployment"
  value       = var.deployment_name
}

output "deployment_id" {
  value       = random_string.deployment_id.result
  description = "Unique deployment identifier"
}

output "node_ids" {
  description = "List of node IDs used in deployment"
  value = [
    var.gateway_node_id,
    var.ai_agent_node_id,
    var.gitea_node_id
  ]
}

output "domain" {
  description = "Configured domain (if any)"
  value       = var.domain != "" ? var.domain : "none (private mode)"
}

# ==============================================================================
# OUTPUTS - Credentials (Sensitive)
# ==============================================================================

output "gateway_api_key" {
  description = "Gateway API authentication key"
  value       = random_password.gateway_api_key.result
  sensitive   = true
}

output "gitea_admin_password" {
  description = "Gitea admin user password"
  value       = random_password.gitea_admin_password.result
  sensitive   = true
}

output "gitea_db_password" {
  description = "Gitea database password"
  value       = random_password.gitea_db_password.result
  sensitive   = true
}

# ==============================================================================
# OUTPUTS - File Paths
# ==============================================================================

output "ssh_config_file" {
  description = "Generated SSH config file path"
  value       = local_file.ssh_config.filename
}

output "credentials_file" {
  description = "Generated credentials file path"
  value       = local_sensitive_file.credentials.filename
}

# ==============================================================================
# OUTPUTS - Summary
# ==============================================================================

output "deployment_summary" {
  description = "Deployment summary"
  value = {
    gateway = {
      mycelium_ip = local.enable_mycelium ? try(grid_deployment.gateway.vms[0].mycelium_ip, "") : ""
      wireguard_ip = local.enable_wireguard ? try(grid_deployment.gateway.vms[0].ip, "") : ""
      public_ip   = local.enable_ipv4 ? try(grid_deployment.gateway.vms[0].computedip, "") : ""
      cpu         = var.gateway_cpu
      memory_mb   = var.gateway_memory
      disk_mb     = var.gateway_disk
    }
    ai_agent = {
      mycelium_ip = local.enable_mycelium ? try(grid_deployment.ai_agent.vms[0].mycelium_ip, "") : ""
      wireguard_ip = local.enable_wireguard ? try(grid_deployment.ai_agent.vms[0].ip, "") : ""
      cpu         = var.ai_agent_cpu
      memory_mb   = var.ai_agent_memory
      disk_mb     = var.ai_agent_disk
    }
    gitea = {
      mycelium_ip = local.enable_mycelium ? try(grid_deployment.gitea.vms[0].mycelium_ip, "") : ""
      wireguard_ip = local.enable_wireguard ? try(grid_deployment.gitea.vms[0].ip, "") : ""
      cpu         = var.gitea_cpu
      memory_mb   = var.gitea_memory
      disk_mb     = var.gitea_disk
    }
    mode            = var.domain != "" ? "public" : "private"
    domain          = var.domain
    deployment_name = var.deployment_name
  }
}

# ==============================================================================
# LEGACY OUTPUTS - For backward compatibility
# ==============================================================================

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

output "gateway_ip" {
  value = (
    local.enable_mycelium ? try(grid_deployment.gateway.vms[0].mycelium_ip, "") :
    local.enable_wireguard ? try(grid_deployment.gateway.vms[0].ip, "") :
    ""
  )
  description = "DEPRECATED: Use gateway_mycelium_ip or gateway_wireguard_ip instead."
}

output "gateway_public_ip" {
  value       = local.enable_ipv4 ? try(grid_deployment.gateway.vms[0].computedip, "") : ""
  description = "DEPRECATED: Use ipv4_address instead."
}

output "ai_agent_ip" {
  value = (
    local.enable_mycelium ? try(grid_deployment.ai_agent.vms[0].mycelium_ip, "") :
    local.enable_wireguard ? try(grid_deployment.ai_agent.vms[0].ip, "") :
    ""
  )
  description = "DEPRECATED: Use ai_agent_mycelium_ip or ai_agent_wireguard_ip instead."
}

output "gitea_ip" {
  value = (
    local.enable_mycelium ? try(grid_deployment.gitea.vms[0].mycelium_ip, "") :
    local.enable_wireguard ? try(grid_deployment.gitea.vms[0].ip, "") :
    ""
  )
  description = "DEPRECATED: Use gitea_mycelium_ip or gitea_wireguard_ip instead."
}
