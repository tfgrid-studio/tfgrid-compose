#!/bin/bash
# Single VM - Health check hook (comprehensive baseline validation)
set -e

echo "=========================================="
echo "  HEALTHCHECK: Validating deployment"
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

# Test 3: HTTPS Connectivity
echo ""
echo "Test 3: HTTPS connectivity..."
if curl -sf https://google.com > /dev/null 2>&1; then
    echo "  ✅ HTTPS working"
else
    echo "  ❌ HTTPS not working"
    ((FAILURES++))
fi

# Test 4: Package Manager
echo ""
echo "Test 4: Package manager..."
if apt-get update > /dev/null 2>&1; then
    echo "  ✅ apt update working"
else
    echo "  ❌ apt update failed"
    ((FAILURES++))
fi

# Test 5: Installed Packages
echo ""
echo "Test 5: Verifying installed packages..."
PACKAGES=("git" "curl" "wget" "nginx" "jq")
for pkg in "${PACKAGES[@]}"; do
    if command -v $pkg > /dev/null 2>&1; then
        echo "  ✅ $pkg installed"
    else
        echo "  ❌ $pkg not found"
        ((FAILURES++))
    fi
done

# Test 6: Nginx Service
echo ""
echo "Test 6: Nginx service..."
if systemctl is-active --quiet nginx; then
    echo "  ✅ Nginx is running"
else
    echo "  ❌ Nginx is not running"
    ((FAILURES++))
fi

# Test 7: Website Accessibility
echo ""
echo "Test 7: Website accessibility..."
if curl -sf http://localhost/ > /dev/null 2>&1; then
    echo "  ✅ Website responds on localhost"
else
    echo "  ❌ Website not responding"
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
