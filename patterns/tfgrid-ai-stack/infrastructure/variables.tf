# TFGrid AI Stack - Terraform Variables
# Version: 0.13.0

# ==============================================================================
# AUTHENTICATION
# ==============================================================================

variable "mnemonic" {
  type        = string
  sensitive   = true
  description = "ThreeFold mnemonic for authentication"
}

variable "tfgrid_network" {
  type        = string
  default     = "main"
  description = "ThreeFold Grid network (main, test, dev)"
}

# ==============================================================================
# NETWORK PROVISIONING
# At least one must be true
# ==============================================================================

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
  description = "DEPRECATED: Use provision_* variables instead."
}

# ==============================================================================
# DEPLOYMENT CONFIGURATION
# ==============================================================================

variable "deployment_name" {
  description = "Deployment name prefix"
  type        = string
  default     = "tfgrid-ai-stack"
}

# ==============================================================================
# NODE SELECTION
# ==============================================================================

variable "farm_id" {
  description = "Farm ID for deployment (0 for auto-select)"
  type        = number
  default     = 0
}

variable "gateway_node_id" {
  description = "Specific node ID for Gateway VM"
  type        = number
}

variable "ai_agent_node_id" {
  description = "Specific node ID for AI Agent VM"
  type        = number
}

variable "gitea_node_id" {
  description = "Specific node ID for Gitea VM"
  type        = number
}

# ==============================================================================
# GATEWAY VM RESOURCES
# ==============================================================================

variable "gateway_cpu" {
  description = "Gateway VM CPU cores"
  type        = number
  default     = 2
  validation {
    condition     = var.gateway_cpu >= 2 && var.gateway_cpu <= 8
    error_message = "Gateway CPU must be between 2 and 8 cores"
  }
}

variable "gateway_memory" {
  description = "Gateway VM memory in MB"
  type        = number
  default     = 4096
  validation {
    condition     = var.gateway_memory >= 2048
    error_message = "Gateway memory must be at least 2048 MB"
  }
}

variable "gateway_disk" {
  description = "Gateway VM disk size in MB"
  type        = number
  default     = 51200
}

# ==============================================================================
# AI AGENT VM RESOURCES
# ==============================================================================

variable "ai_agent_cpu" {
  description = "AI Agent VM CPU cores"
  type        = number
  default     = 4
  validation {
    condition     = var.ai_agent_cpu >= 2
    error_message = "AI Agent CPU must be at least 2 cores"
  }
}

variable "ai_agent_memory" {
  description = "AI Agent VM memory in MB"
  type        = number
  default     = 8192
  validation {
    condition     = var.ai_agent_memory >= 4096
    error_message = "AI Agent memory must be at least 4096 MB"
  }
}

variable "ai_agent_disk" {
  description = "AI Agent VM disk size in MB"
  type        = number
  default     = 102400
}

# ==============================================================================
# GITEA VM RESOURCES
# ==============================================================================

variable "gitea_cpu" {
  description = "Gitea VM CPU cores"
  type        = number
  default     = 2
}

variable "gitea_memory" {
  description = "Gitea VM memory in MB"
  type        = number
  default     = 4096
}

variable "gitea_disk" {
  description = "Gitea VM disk size in MB"
  type        = number
  default     = 51200
}

# ==============================================================================
# DOMAIN & SSL
# ==============================================================================

variable "domain" {
  description = "Domain name for public access (empty for private mode)"
  type        = string
  default     = ""
}

variable "ssl_email" {
  description = "Email for SSL certificate registration"
  type        = string
  default     = ""
}

# ==============================================================================
# SSH CONFIGURATION
# ==============================================================================

variable "ssh_key" {
  description = "SSH public key for VM access (auto-detect if empty)"
  type        = string
  default     = ""
}

variable "SSH_KEY" {
  description = "SSH public key (alias for ssh_key)"
  type        = string
  default     = ""
}

variable "ssh_key_path" {
  description = "Path to SSH private key file"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

# ==============================================================================
# GITEA CONFIGURATION
# ==============================================================================

variable "gitea_admin_user" {
  description = "Gitea admin username"
  type        = string
  default     = "gitadmin"
}

variable "gitea_admin_email" {
  description = "Gitea admin email"
  type        = string
  default     = "admin@localhost"
}
