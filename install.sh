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

# Check for tfcmd dependency (required for grid operations)
echo "🔍 Checking tfcmd dependency..."
if ! command -v tfcmd >/dev/null 2>&1; then
    echo ""
    echo "⚠️  tfcmd not found - Required for ThreeFold Grid operations"
    echo ""
    echo "tfcmd is now essential for:"
    echo "  • Contract validation and management"
    echo "  • Grid-authoritative deployment status"
    echo "  • Docker-style deployment operations"
    echo ""
    echo "Install tfcmd:"
    echo "  curl -fsSL https://raw.githubusercontent.com/threefoldtech/tfcmd/main/install.sh | bash"
    echo ""
    echo "Or visit: https://github.com/threefoldtech/tfcmd"
    echo ""
    read -p "Install tfcmd now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🚀 Installing tfcmd..."
        if curl -fsSL https://raw.githubusercontent.com/threefoldtech/tfcmd/main/install.sh | bash; then
            echo "✅ tfcmd installed successfully"
        else
            echo "❌ tfcmd installation failed"
            echo "Please install manually: https://github.com/threefoldtech/tfcmd"
        fi
    else
        echo "⚠️  Continuing without tfcmd - Some features may not work"
    fi
else
    echo "✅ tfcmd found - Grid operations enabled"
fi

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
