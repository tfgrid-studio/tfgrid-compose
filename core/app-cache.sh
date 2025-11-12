#!/usr/bin/env bash
# TFGrid Compose - Enhanced App Cache Module
# Handles downloading, caching, and version tracking app repositories

# Load the enhanced cache module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/app-cache-enhanced.sh"
