# TFGrid AI Stack - Terraform Outputs
# Version: 0.12.0-dev (MVP)

# Gateway VM Outputs
output "gateway_ip" {
  description = "Gateway VM IP address (Planetary/Yggdrasil)"
  value       = grid_deployment.gateway.vms[0].ygg_ip
}

output "gateway_public_ip" {
  description = "Gateway VM public IP (if domain specified)"
  value       = var.domain != "" ? grid_deployment.gateway.vms[0].computedip : null
}

output "gateway_planetary_ip" {
  description = "Gateway VM Planetary Network IP"
  value       = grid_deployment.gateway.vms[0].planetary_ip
}

# AI Agent VM Outputs
output "ai_agent_ip" {
  description = "AI Agent VM IP address"
  value       = grid_deployment.ai_agent.vms[0].ygg_ip
}

output "ai_agent_planetary_ip" {
  description = "AI Agent VM Planetary Network IP"
  value       = grid_deployment.ai_agent.vms[0].planetary_ip
}

# Gitea VM Outputs
output "gitea_ip" {
  description = "Gitea VM IP address"
  value       = grid_deployment.gitea.vms[0].ygg_ip
}

output "gitea_planetary_ip" {
  description = "Gitea VM Planetary Network IP"
  value       = grid_deployment.gitea.vms[0].planetary_ip
}

# Credentials (Sensitive)
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

# Deployment Info
output "deployment_name" {
  description = "Deployment name"
  value       = var.deployment_name
}

output "domain" {
  description = "Configured domain (if any)"
  value       = var.domain != "" ? var.domain : "none (private mode)"
}

# SSH Config File
output "ssh_config_file" {
  description = "Generated SSH config file path"
  value       = local_file.ssh_config.filename
}

# Credentials File
output "credentials_file" {
  description = "Generated credentials file path"
  value       = local_sensitive_file.credentials.filename
}

# Access Instructions
output "access_instructions" {
  description = "How to access the deployed VMs"
  value = <<-EOT
    ╔════════════════════════════════════════════════════════════╗
    ║          TFGrid AI Stack - Deployment Complete             ║
    ╚════════════════════════════════════════════════════════════╝
    
    📡 Gateway VM:
       IP: ${grid_deployment.gateway.vms[0].ygg_ip}
       ${var.domain != "" ? "Public URL: https://${var.domain}" : "Mode: Private"}
       SSH: ssh -F ${local_file.ssh_config.filename} gateway
    
    🤖 AI Agent VM:
       IP: ${grid_deployment.ai_agent.vms[0].ygg_ip}
       SSH: ssh -F ${local_file.ssh_config.filename} ai-agent
    
    📦 Gitea VM:
       IP: ${grid_deployment.gitea.vms[0].ygg_ip}
       SSH: ssh -F ${local_file.ssh_config.filename} gitea
    
    🔐 Credentials:
       Saved to: ${local_sensitive_file.credentials.filename}
       View: cat ${local_sensitive_file.credentials.filename}
    
    ⚙️  Next Steps:
       1. Run Ansible to configure services:
          cd ../platform && ansible-playbook -i inventory.ini site.yml
       
       2. Wait for services to start (~5 minutes)
       
       3. Test deployment:
          ../scripts/health-check.sh
       
       4. Create your first project:
          tfgrid-compose create "hello world website"
    
    📚 Documentation: ../README.md
    ❓ Troubleshooting: ../docs/TROUBLESHOOTING.md
  EOT
}

# Summary Output
output "deployment_summary" {
  description = "Deployment summary"
  value = {
    gateway = {
      ip              = grid_deployment.gateway.vms[0].ygg_ip
      public_ip       = var.domain != "" ? grid_deployment.gateway.vms[0].computedip : null
      cpu             = var.gateway_cpu
      memory_mb       = var.gateway_memory
      disk_mb         = var.gateway_disk
    }
    ai_agent = {
      ip              = grid_deployment.ai_agent.vms[0].ygg_ip
      cpu             = var.ai_agent_cpu
      memory_mb       = var.ai_agent_memory
      disk_mb         = var.ai_agent_disk
    }
    gitea = {
      ip              = grid_deployment.gitea.vms[0].ygg_ip
      cpu             = var.gitea_cpu
      memory_mb       = var.gitea_memory
      disk_mb         = var.gitea_disk
    }
    mode               = var.domain != "" ? "public" : "private"
    domain             = var.domain
    deployment_name    = var.deployment_name
  }
}