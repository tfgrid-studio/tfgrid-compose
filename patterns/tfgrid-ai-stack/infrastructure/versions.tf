# TFGrid AI Stack - Provider Versions
# Version: 0.12.0-dev (MVP)

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    grid = {
      source  = "threefold/grid"
      version = "~> 1.9.0"
    }
    
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4.0"
    }
  }
}

# ThreeFold Grid Provider Configuration
provider "grid" {
  # Mnemonics should be provided via environment variable:
  # export MNEMONICS="your twelve word seed phrase here"
  
  # Or via terraform.tfvars (not recommended for production):
  # mnemonics = var.grid_mnemonics
  
  # Network selection (mainnet, testnet, devnet)
  network = var.grid_network
}

# Additional provider configuration
variable "grid_network" {
  description = "ThreeFold Grid network (mainnet, testnet, devnet)"
  type        = string
  default     = "mainnet"
  
  validation {
    condition     = contains(["mainnet", "testnet", "devnet"], var.grid_network)
    error_message = "Grid network must be mainnet, testnet, or devnet"
  }
}