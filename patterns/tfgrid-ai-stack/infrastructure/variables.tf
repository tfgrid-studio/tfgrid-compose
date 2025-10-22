# TFGrid AI Stack - Terraform Variables
# Version: 0.12.0-dev (MVP)

variable "deployment_name" {
  description = "Deployment name prefix"
  type        = string
  default     = "tfgrid-ai-stack"
}

# VM Resource Allocation
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

# Network Configuration
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

# SSH Configuration
variable "ssh_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "ssh_key_path" {
  description = "Path to SSH private key file"
  type        = string
  default     = "~/.ssh/id_rsa"
}

# ThreeFold Grid Configuration
variable "farm_id" {
  description = "Farm ID for deployment (0 for auto-select)"
  type        = number
  default     = 0
}

variable "gateway_node_id" {
  description = "Specific node ID for Gateway VM (0 for auto)"
  type        = number
  default     = 0
}

variable "ai_agent_node_id" {
  description = "Specific node ID for AI Agent VM (0 for auto)"
  type        = number
  default     = 0
}

variable "gitea_node_id" {
  description = "Specific node ID for Gitea VM (0 for auto)"
  type        = number
  default     = 0
}

# Gitea Configuration
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