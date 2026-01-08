#!/usr/bin/env bash
# TFGrid Compose - Network Module Tests
# Comprehensive test suite for network management functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the network module
source "$PROJECT_ROOT/core/network.sh"

# Source common functions for logging
source "$PROJECT_ROOT/core/common.sh" 2>/dev/null || true

# Test counter and results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
test_start() {
    local test_name="$1"
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "🧪 Running test: $test_name"
}

test_pass() {
    local test_name="$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "✅ PASS: $test_name"
}

test_fail() {
    local test_name="$1"
    local reason="$2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "❌ FAIL: $test_name - $reason"
}

# Test data setup - simplified for new deployments only
setup_test_data() {
    # Create test deployment state directories
    export STATE_BASE_DIR="/tmp/test-state-$RANDOM"
    export TEST_APP_WG_DIR="$STATE_BASE_DIR/test-app-wg-123"
    export TEST_APP_MY_DIR="$STATE_BASE_DIR/test-app-my-456"

    mkdir -p "$TEST_APP_WG_DIR" "$TEST_APP_MY_DIR"
    mkdir -p "$HOME/.config/tfgrid-compose"

    # Create test state files
    cat > "$TEST_APP_WG_DIR/state.yaml" << 'EOF'
preferred_network: wireguard
ipv4_address: 192.168.1.100
wormhole_ip: 192.168.1.101
network_config:
  wireguard_public_key: test-key-123
  wireguard_private_key: test-private-key
  wireguard_endpoint: grid.tf:8090
EOF

    cat > "$TEST_APP_MY_DIR/state.yaml" << 'EOF'
preferred_network: mycelium
ipv4_address: 192.168.2.100
mycelium_address: 200::1
wormhole_ip: 192.168.2.101
network_config:
  mycelium_public_key: mycelium-test-key
EOF
}

cleanup_test_data() {
    if [ -n "$STATE_BASE_DIR" ] && [ -d "$STATE_BASE_DIR" ]; then
        rm -rf "$STATE_BASE_DIR"
    fi
    # Clean up any global state modifications
    unset STATE_BASE_DIR TEST_APP_WG_DIR TEST_APP_MY_DIR
}

# Unit tests for utility functions
test_get_network_preference() {
    test_start "get_network_preference"

    # Test with specific deployment preference
    local result=$(get_network_preference "test-app-wg")
    if [ "$result" = "wireguard" ]; then
        test_pass "get_network_preference - wireguard deployment"
    else
        test_fail "get_network_preference - wireguard deployment" "Expected 'wireguard', got '$result'"
    fi

    # Test with mycelium deployment preference
    result=$(get_network_preference "test-app-my")
    if [ "$result" = "mycelium" ]; then
        test_pass "get_network_preference - mycelium deployment"
    else
        test_fail "get_network_preference - mycelium deployment" "Expected 'mycelium', got '$result'"
    fi

    # Test with unknown deployment (should use default)
    result=$(get_network_preference "unknown-app")
    if [ "$result" = "wireguard" ]; then
        test_pass "get_network_preference - default for unknown"
    else
        test_fail "get_network_preference - default for unknown" "Expected 'wireguard', got '$result'"
    fi
}

test_get_deployment_ip() {
    test_start "get_deployment_ip"

    # Test WireGuard IP resolution
    local result=$(get_deployment_ip "test-app-wg-123")
    if [ "$result" = "192.168.1.100" ]; then
        test_pass "get_deployment_ip - wireguard"
    else
        test_fail "get_deployment_ip - wireguard" "Expected '192.168.1.100', got '$result'"
    fi

    # Test Mycelium IP resolution
    result=$(get_deployment_ip "test-app-my-456")
    if [ "$result" = "200::1" ]; then
        test_pass "get_deployment_ip - mycelium"
    else
        test_fail "get_deployment_ip - mycelium" "Expected '200::1', got '$result'"
    fi
}

test_set_network_preference() {
    test_start "set_network_preference"

    # Test valid network setting
    if set_network_preference "test-app-set" "mycelium"; then
        test_pass "set_network_preference - valid mycelium"
    else
        test_fail "set_network_preference - valid mycelium" "Failed to set mycelium preference"
    fi

    # Test invalid network setting
    if ! set_network_preference "test-app-set" "invalid-net"; then
        test_pass "set_network_preference - invalid network rejected"
    else
        test_fail "set_network_preference - invalid network rejected" "Should reject invalid network"
    fi
}

test_network_preference_storage() {
    test_start "network_preference_storage"

    # Test setting network preference
    if set_network_preference "test-deployment" "mycelium"; then
        test_pass "set_network_preference"
    else
        test_fail "set_network_preference" "Failed to set preference"
    fi

    # Test getting the preference back
    local result=$(get_network_preference "test-deployment")
    if [ "$result" = "mycelium" ]; then
        test_pass "get_network_preference after set"
    else
        test_fail "get_network_preference after set" "Expected 'mycelium', got '$result'"
    fi
}

# Integration tests for network commands
test_network_info_command() {
    test_start "network_info_command_integration"

    # Mock command output capture
    local output=""
    if network_info_command > /tmp/network_info_test 2>&1; then
        output=$(cat /tmp/network_info_test)
        if echo "$output" | grep -q "Network Status"; then
            test_pass "network_info_command - basic output"
        else
            test_fail "network_info_command - basic output" "Missing expected content"
        fi
    else
        test_fail "network_info_command_integration" "Command failed"
    fi

    rm -f /tmp/network_info_test
}

test_network_preference_command() {
    test_start "network_preference_command_integration"

    # Test setting preference
    if network_preference_command set "test-deployment" "mycelium" > /tmp/pref_test 2>&1; then
        local result=$(get_network_preference "test-deployment")
        if [ "$result" = "mycelium" ]; then
            test_pass "network_preference_command set"
        else
            test_fail "network_preference_command set" "Preference not set correctly"
        fi
    else
        test_fail "network_preference_command_integration" "Command failed"
    fi

    rm -f /tmp/pref_test
}

test_network_switch_command() {
    test_start "network_switch_command_integration"

    # Test switching network - this would normally require a running deployment
    # For testing, we'll just check the function exists and can be called
    if network_switch_command help > /tmp/switch_test 2>&1 2>/dev/null && echo "success" >/tmp/switch_test; then
        test_pass "network_switch_command - can be called"
    else
        test_fail "network_switch_command_integration" "Command failed or not available"
    fi

    rm -f /tmp/switch_test
}

# Performance tests
test_network_command_performance() {
    test_start "network_command_performance"

    local start_time=$(date +%s%N)
    local iterations=10

    for i in $(seq 1 $iterations); do
        get_network_preference "test-app-wg" >/dev/null 2>&1
    done

    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds

    # Should complete in reasonable time (< 100ms per iteration)
    local max_expected=$((iterations * 100))
    if [ $duration -lt $max_expected ]; then
        test_pass "network_command_performance - $duration ms for $iterations calls"
    else
        test_fail "network_command_performance" "Too slow: $duration ms for $iterations calls"
    fi
}

# Error handling tests
test_error_handling() {
    test_start "error_handling"

    # Test with invalid network type
    if ! set_network_preference "test-app" "invalid-network"; then
        test_pass "error_handling - invalid network rejected"
    else
        test_fail "error_handling - invalid network rejected" "Should reject invalid network"
    fi

    # Test with empty deployment name
    if ! set_network_preference "" "wireguard"; then
        test_pass "error_handling - empty deployment name"
    else
        test_fail "error_handling - empty deployment name" "Should reject empty deployment"
    fi
}

# Security tests (basic)
test_security_basic() {
    test_start "security_basic"

    # Test that network preferences file has restricted permissions
    if [ -f "$TFGRID_NETWORK_PREFERENCES_FILE" ]; then
        local perms=$(stat -c '%a' "$TFGRID_NETWORK_PREFERENCES_FILE" 2>/dev/null || echo "unknown")
        if [ "$perms" = "600" ]; then
            test_pass "security_basic - file permissions"
        else
            test_fail "security_basic - file permissions" "Expected 600, got $perms"
        fi
    else
        test_fail "security_basic - file permissions" "Preferences file missing"
    fi
}

# Main test runner
run_all_tests() {
    echo "🧪 Starting TFGrid Network Module Test Suite"
    echo "=============================================="
    echo ""

    # Setup
    setup_test_data

    # Run unit tests
    echo "📋 Unit Tests:"
    echo "--------------"
    test_get_network_preference
    test_get_deployment_ip
    test_set_network_preference
    test_network_preference_storage
    echo ""

    # Run integration tests
    echo "🔗 Integration Tests:"
    echo "---------------------"
    test_network_info_command
    test_network_preference_command
    test_network_switch_command
    echo ""

    # Run performance tests
    echo "⚡ Performance Tests:"
    echo "--------------------"
    test_network_command_performance
    echo ""

    # Run error handling tests
    echo "🛡️  Error Handling Tests:"
    echo "-------------------------"
    test_error_handling
    echo ""

    # Run security tests
    echo "🔐 Security Tests:"
    echo "------------------"
    test_security_basic
    echo ""

    # Cleanup
    cleanup_test_data

    # Results
    echo "📊 Test Results:"
    echo "================="
    echo "Tests run:    $TESTS_RUN"
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo "🎉 All tests passed!"
        exit 0
    else
        echo "❌ $TESTS_FAILED tests failed"
        exit 1
    fi
}

# Allow running specific test groups
if [ $# -gt 0 ]; then
    case "$1" in
        unit)
            echo "Running unit tests only..."
            setup_test_data
            test_get_network_preference
            test_get_deployment_ip
            test_set_network_preference
            test_network_preference_storage
            cleanup_test_data
            ;;
        integration)
            echo "Running integration tests only..."
            setup_test_data
            test_network_info_command
            test_network_preference_command
            test_network_switch_command
            cleanup_test_data
            ;;
        performance)
            echo "Running performance tests only..."
            setup_test_data
            test_network_command_performance
            cleanup_test_data
            ;;
        *)
            echo "Usage: $0 [unit|integration|performance]"
            echo "Run without arguments for full test suite"
            exit 1
            ;;
    esac
else
    run_all_tests
fi
