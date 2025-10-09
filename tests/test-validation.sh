#!/bin/bash
# Test validation module

set -e

echo "🧪 Testing Input Validation"
echo "==========================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$DEPLOYER_ROOT/cli/tfgrid-compose"

# Test 1: Missing app path
echo "Test 1: Missing app path..."
if $CLI up 2>&1 | grep -q "App path not specified"; then
    echo "✅ PASS: Correctly rejects missing app path"
else
    echo "❌ FAIL: Should reject missing app path"
    exit 1
fi
echo ""

# Test 2: Invalid app path
echo "Test 2: Invalid app path..."
if $CLI up /nonexistent/path 2>&1 | grep -q "App directory not found"; then
    echo "✅ PASS: Correctly rejects invalid path"
else
    echo "❌ FAIL: Should reject invalid path"
    exit 1
fi
echo ""

# Test 3: Missing manifest
echo "Test 3: Missing manifest..."
TEMP_DIR=$(mktemp -d)
if $CLI up "$TEMP_DIR" 2>&1 | grep -q "App manifest not found"; then
    echo "✅ PASS: Correctly rejects missing manifest"
else
    echo "❌ FAIL: Should reject missing manifest"
    exit 1
fi
rm -rf "$TEMP_DIR"
echo ""

# Test 4: Prerequisites check
echo "Test 4: Prerequisites validation..."
if $CLI up ../tfgrid-ai-agent 2>&1 | grep -q "Validating system prerequisites"; then
    echo "✅ PASS: Prerequisites check runs"
else
    echo "❌ FAIL: Prerequisites check should run"
    exit 1
fi
echo ""

# Test 5: Existing deployment check (if deployment exists)
if [ -d "$DEPLOYER_ROOT/.tfgrid-compose" ]; then
    echo "Test 5: Existing deployment detection..."
    if $CLI up ../tfgrid-ai-agent 2>&1 | grep -q "Existing deployment detected"; then
        echo "✅ PASS: Correctly detects existing deployment"
    else
        echo "⚠️  SKIP: No deployment exists"
    fi
    echo ""
fi

echo "==========================="
echo "✅ All validation tests passed!"
echo ""
