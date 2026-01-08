#!/bin/bash
# Qwen OAuth login helper - automated with expect
set -e

# Get VM IP from environment or state
if [ -z "$VM_IP" ]; then
    VM_IP=$(cat .tfgrid-compose/state.yaml 2>/dev/null | grep '^ipv4_address:' | awk '{print $2}')
fi

if [ -z "$VM_IP" ]; then
    echo "❌ No deployment found. Run 'make up' or 'tfgrid-compose up' first."
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

# Create the expect script on the VM directly as developer user
ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@$VM_IP 'su - developer -c "cat > ~/qwen-auth.sh"' <<'REMOTE_SCRIPT'
#!/bin/bash
# Clean previous auth
rm -rf ~/.qwen

# Use expect to automate the OAuth device flow
expect <<'END_EXPECT' > ~/qwen_oauth.log 2>&1 &
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

# Make it executable and run as developer user
ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@$VM_IP 'su - developer -c "chmod +x ~/qwen-auth.sh && bash ~/qwen-auth.sh" &'

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
    root@$VM_IP 'su - developer -c "cat ~/qwen_oauth.log 2>/dev/null | grep -E \"https://.*authorize\" | head -20 || echo \"⚠️  Waiting for OAuth URL...\""'
echo ""

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "✅ Press ENTER after completing OAuth in your browser..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Kill the qwen/expect processes (kill as developer's processes)
ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    root@$VM_IP 'pkill -u developer -f qwen 2>/dev/null || true; pkill -u developer -f expect 2>/dev/null || true' || true

echo ""
echo "Authentication session ended."
echo ""
echo "Verifying authentication status..."

if ssh -o LogLevel=ERROR -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    root@$VM_IP "su - developer -c 'test -f ~/.qwen/settings.json'" &>/dev/null; then
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
    echo "  4. Check: ssh root@$VM_IP 'su - developer -c \"ls -la ~/.qwen\"'"
fi
