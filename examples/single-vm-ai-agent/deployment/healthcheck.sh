#!/bin/bash
# AI Agent - Health check hook (validates AI agent deployment)
set -e

echo "=========================================="
echo "  HEALTHCHECK: Validating AI Agent deployment"
echo "=========================================="
echo ""

FAILURES=0

# Test 1: Internet Connectivity
echo "Test 1: Internet connectivity..."
if ping -c 2 8.8.8.8 > /dev/null 2>&1; then
    echo "  ✅ Can reach 8.8.8.8"
else
    echo "  ❌ Cannot reach 8.8.8.8"
    ((FAILURES++))
fi

# Test 2: DNS Resolution
echo ""
echo "Test 2: DNS resolution..."
if host google.com > /dev/null 2>&1; then
    echo "  ✅ DNS working (google.com resolved)"
else
    echo "  ❌ DNS not working"
    ((FAILURES++))
fi

# Test 3: Package Manager
echo ""
echo "Test 3: Package manager..."
if apt-get update > /dev/null 2>&1; then
    echo "  ✅ apt update working"
else
    echo "  ❌ apt update failed"
    ((FAILURES++))
fi

# Test 4: AI Agent Dependencies
echo ""
echo "Test 4: Verifying AI agent dependencies..."
PACKAGES=("git" "curl" "wget" "python3" "jq" "tmux")
for pkg in "${PACKAGES[@]}"; do
    if command -v $pkg > /dev/null 2>&1; then
        echo "  ✅ $pkg installed"
    else
        echo "  ❌ $pkg not found"
        ((FAILURES++))
    fi
done

# Test 5: Node.js (if installed)
echo ""
echo "Test 5: Node.js..."
if command -v node > /dev/null 2>&1; then
    NODE_VERSION=$(node --version)
    echo "  ✅ Node.js installed: $NODE_VERSION"
else
    echo "  ⚠️  Node.js not found (may be installed later via Ansible)"
fi

# Test 6: Qwen CLI (if installed)
echo ""
echo "Test 6: Qwen CLI..."
if command -v qwen > /dev/null 2>&1; then
    echo "  ✅ Qwen CLI installed"
else
    echo "  ⚠️  Qwen CLI not found (may be installed later via Ansible)"
fi

# Test 7: AI Agent Directory
echo ""
echo "Test 7: AI agent workspace..."
if [ -d "/opt/ai-agent-projects" ]; then
    echo "  ✅ AI agent workspace exists"
else
    echo "  ❌ AI agent workspace missing"
    ((FAILURES++))
fi

# Test 8: Network Services
echo ""
echo "Test 8: Network services..."
if command -v wg > /dev/null 2>&1 && wg show > /dev/null 2>&1; then
    echo "  ✅ WireGuard configured"
else
    echo "  ⚠️  WireGuard not detected (may be OK)"
fi

if command -v mycelium > /dev/null 2>&1; then
    echo "  ✅ Mycelium installed"
else
    echo "  ⚠️  Mycelium not detected (may be OK)"
fi

# Final Result
echo ""
echo "=========================================="
if [ $FAILURES -eq 0 ]; then
    echo "✅ ALL HEALTH CHECKS PASSED"
    echo "=========================================="
    exit 0
else
    echo "❌ HEALTH CHECK FAILED ($FAILURES failures)"
    echo "=========================================="
    exit 1
fi