#!/bin/bash
# Install tfgrid-compose CLI to system PATH

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Installing TFGrid Compose..."
echo ""

# Determine install location
if [ -w /usr/local/bin ]; then
    INSTALL_DIR="/usr/local/bin"
    NEEDS_SUDO=false
else
    INSTALL_DIR="$HOME/.local/bin"
    NEEDS_SUDO=false
    
    # Create directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"
    
    # Check if it's in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo "⚠️  $INSTALL_DIR is not in your PATH"
        echo ""
        echo "Add this line to your shell config (~/.bashrc, ~/.zshrc, or ~/.config/fish/config.fish):"
        echo ""
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "❌ Installation cancelled"
            exit 1
        fi
    fi
fi

# Create symlink
TFGRID_COMPOSE="$SCRIPT_DIR/cli/tfgrid-compose"

if [ ! -f "$TFGRID_COMPOSE" ]; then
    echo "❌ Error: tfgrid-compose CLI not found at $TFGRID_COMPOSE"
    exit 1
fi

# Make executable
chmod +x "$TFGRID_COMPOSE"

# Create symlink
echo "📦 Installing to $INSTALL_DIR..."
if [ "$NEEDS_SUDO" = true ]; then
    sudo ln -sf "$TFGRID_COMPOSE" "$INSTALL_DIR/tfgrid-compose"
else
    ln -sf "$TFGRID_COMPOSE" "$INSTALL_DIR/tfgrid-compose"
fi

echo "✅ Installation complete!"
echo ""
echo "Test it:"
echo "  tfgrid-compose --version"
echo ""
echo "Get started:"
echo "  tfgrid-compose help"
echo "  tfgrid-compose up <app-path>"
echo ""
