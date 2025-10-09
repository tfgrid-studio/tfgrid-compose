#!/bin/bash
# Qwen OAuth login helper - automated with expect
set -e

# Get VM IP from state
VM_IP=$(cat .tfgrid-compose/state.yaml 2>/dev/null | grep '^vm_ip:' | awk '{print $2}')

if [ -z "$VM_IP" ]; then
    echo "❌ No deployment found. Run 'make up' first."
    exit 1
fi

echo "🔐 Qwen OAuth Authentication"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📋 OAuth Authentication Steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Qwen will display an authorization URL below"
echo "2. COPY the URL manually"
echo "3. PASTE and open it in your LOCAL web browser"
echo "4. Sign in with your Google account (or other OAuth provider)"
echo "5. Authorize Qwen Code"
echo "6. Come back here and press ENTER"
echo ""
echo "💡 TIP: The URL looks like:"
echo "   https://chat.qwen.ai/authorize?user_code=XXXXXXXX&client=qwen-code"
echo ""
read -p "Press Enter when ready to start (or Ctrl+C to cancel)..."
echo ""

echo "🔓 Starting Qwen authentication session..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Start qwen with expect in background on the VM
ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@$VM_IP 'bash' <<'REMOTE_SCRIPT' &
# Clean previous auth
rm -rf ~/.qwen

# Use expect to automate the OAuth device flow
nohup expect <<'END_EXPECT' > /tmp/qwen_oauth.log 2>&1 &
set timeout 180
log_user 1

spawn qwen
expect {
    "How would you like to authenticate" {
        send "1\r"
        expect {
            "authorize" {
                # Keep session alive until killed
                expect timeout
            }
        }
    }
}
END_EXPECT

REMOTE_SCRIPT

# Wait for OAuth URL to appear
echo "Waiting for OAuth URL..."
sleep 8

# Display the OAuth output - grep for the actual URL
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 OAuth URL (copy and open in your browser):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@$VM_IP 'grep -E "https://.*authorize" /tmp/qwen_oauth.log 2>/dev/null || cat /tmp/qwen_oauth.log 2>/dev/null || echo "⚠️  URL not found yet, check /tmp/qwen_oauth.log on VM"'
echo ""

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "✅ Press ENTER after completing OAuth in your browser..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Kill the qwen/expect processes
ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@$VM_IP 'pkill -f "qwen" 2>/dev/null || true; pkill -f "expect" 2>/dev/null || true' || true

echo ""
echo "Authentication session ended."
echo ""
echo "Verifying authentication status..."

if ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    root@$VM_IP "test -f ~/.qwen/settings.json" &>/dev/null; then
    echo "✅ Qwen is now authenticated!"
    echo ""
    echo "Next steps:"
    echo "  make create project=my-app"
    echo "  make run project=my-app"
else
    echo "⚠️  Authentication verification failed."
    echo ""
    echo "Troubleshooting:"
    echo "  1. Try running 'make login' again"
    echo "  2. Ensure you completed the OAuth flow in your browser"
    echo "  3. Check VM internet connectivity"
fi
