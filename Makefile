.PHONY: help init up down clean logs status ssh address patterns test verify \
        terraform wireguard wg wait-ssh inventory ansible

# Default app (can be overridden by environment variable or command line)
APP ?=

# Default target
help:
	@echo "╔═══════════════════════════════════════════════════════════════╗"
	@echo "║  TFGrid Compose - Universal Deployment Orchestrator           ║"
	@echo "║  Status: ✅ Production Ready (v0.10.0)                        ║"
	@echo "╚═══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📚 Full Documentation: docs/QUICKSTART.md"
	@echo "🔧 CLI Help: ./cli/tfgrid-compose help"
	@echo ""
	@echo "🚀 Quick Start (First Time):"
	@echo "  1. Configure: mkdir -p ~/.config/threefold"
	@echo "     echo 'your mnemonic' > ~/.config/threefold/mnemonic"
	@echo "  2. Deploy:    make up APP=../tfgrid-ai-agent"
	@echo "  3. Use:       make exec APP=../tfgrid-ai-agent CMD='login'"
	@echo "  4. Destroy:   make down APP=../tfgrid-ai-agent"
	@echo ""
	@echo "⚡ Main Commands:"
	@echo "  make up APP=<app>               - Deploy application (2-3 min)"
	@echo "  make exec APP=<app> CMD='<cmd>' - Execute command on deployed VM"
	@echo "  make status APP=<app>           - Check deployment status"
	@echo "  make ssh APP=<app>              - SSH into deployment"
	@echo "  make connect                    - Quick SSH as developer (uses context)"
	@echo "  make down APP=<app>             - Destroy deployment"
	@echo ""
	@echo "🤖 AI Agent Workflow (Clean & Simple):"
	@echo "  export APP=../tfgrid-ai-agent   # Set once"
	@echo "  make up                         # Deploy"
	@echo "  make login                      # Login to Qwen (one-time)"
	@echo "  make create                     # Create project (interactive)"
	@echo "  make run project=my-app         # Run agent loop"
	@echo "  make list                       # List all projects & status"
	@echo "  make monitor project=my-app     # Watch progress"
	@echo "  make stop project=my-app        # Stop agent"
	@echo "  make down                       # Cleanup"
	@echo ""
	@echo "🛠️  Advanced (Individual Tasks):"
	@echo "  make terraform APP=<app>  - Deploy infrastructure only"
	@echo "  make wg                   - Setup WireGuard only"
	@echo "  make ansible              - Run platform config only"
	@echo "  make inventory            - Generate Ansible inventory"
	@echo ""
	@echo "📋 Utilities:"
	@echo "  make install    - Install tfgrid-compose to PATH"
	@echo "  make uninstall  - Remove tfgrid-compose from PATH"
	@echo "  make patterns   - List deployment patterns"
	@echo "  make ping       - Test connectivity to VM"
	@echo "  make verify     - Verify deployment health"
	@echo "  make clean      - Clean local state"
	@echo "  make help       - Show this help"
	@echo ""
	@echo "💡 Pro Tip: Set APP as environment variable"
	@echo "  Fish: set -x APP ../tfgrid-ai-agent"
	@echo "  Bash: export APP=../tfgrid-ai-agent"
	@echo "  Then: make up, make exec CMD='<cmd>', make down"

# Initialize app configuration
init:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		echo "Usage: make init APP=../tfgrid-ai-agent"; \
		echo "Or set: export APP=../tfgrid-ai-agent"; \
		exit 1; \
	fi
	./cli/tfgrid-compose init $(APP)

# Deploy application
up:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		echo "Usage: make up APP=../tfgrid-ai-agent"; \
		echo "Or set: export APP=../tfgrid-ai-agent"; \
		exit 1; \
	fi
	./cli/tfgrid-compose up $(APP)

deploy:
	make up

# Destroy deployment
down:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		echo "Or set: export APP=../tfgrid-ai-agent"; \
		exit 1; \
	fi
	./cli/tfgrid-compose down $(APP)

# Install tfgrid-compose to system PATH
install:
	@echo "📦 Installing tfgrid-compose..."
	@if [ ! -d "$$HOME/.local/bin" ]; then \
		mkdir -p "$$HOME/.local/bin"; \
		echo "✅ Created ~/.local/bin"; \
	fi
	@if [ ! -d "$$HOME/.local/share/tfgrid-compose" ]; then \
		mkdir -p "$$HOME/.local/share/tfgrid-compose"; \
		echo "✅ Created ~/.local/share/tfgrid-compose"; \
	fi
	@echo "📋 Copying files..."
	@cp -r cli core patterns dashboard "$$HOME/.local/share/tfgrid-compose/"
	@cp VERSION "$$HOME/.local/share/tfgrid-compose/"
	@chmod +x "$$HOME/.local/share/tfgrid-compose/VERSION"
	@echo "💾 Saving version info..."
	@if [ -d ".git" ]; then \
		COMMIT_HASH=$$(git rev-parse --short=7 HEAD 2>/dev/null || echo "unknown"); \
		if [ "$$COMMIT_HASH" != "unknown" ]; then \
			echo "$$COMMIT_HASH" > "$$HOME/.local/share/tfgrid-compose/.version"; \
			echo "✅ Saved commit: $$COMMIT_HASH"; \
		fi; \
	fi
	@echo "#!/usr/bin/env bash" > "$$HOME/.local/bin/tfgrid-compose"
	@echo "exec \"$$HOME/.local/share/tfgrid-compose/cli/tfgrid-compose\" \"\$$@\"" >> "$$HOME/.local/bin/tfgrid-compose"
	@chmod +x "$$HOME/.local/bin/tfgrid-compose"
	@chmod +x "$$HOME/.local/share/tfgrid-compose/cli/tfgrid-compose"
	@echo "✅ Installed to ~/.local/bin/tfgrid-compose"
	@echo ""
	@echo "🔗 Creating default shortcut..."
	@ln -sf "$$HOME/.local/bin/tfgrid-compose" "$$HOME/.local/bin/tfgrid"
	@echo "✅ Created shortcut: tfgrid -> tfgrid-compose"
	@echo ""
	@echo "🔧 Setting up PATH..."
	@if [ -n "$$FISH_VERSION" ] || [ -f "$$HOME/.config/fish/config.fish" ]; then \
		if ! grep -q "$$HOME/.local/bin" "$$HOME/.config/fish/config.fish" 2>/dev/null; then \
			mkdir -p "$$HOME/.config/fish"; \
			echo "" >> "$$HOME/.config/fish/config.fish"; \
			echo "# Added by tfgrid-compose" >> "$$HOME/.config/fish/config.fish"; \
			echo "set -x PATH \$$HOME/.local/bin \$$PATH" >> "$$HOME/.config/fish/config.fish"; \
			echo "✅ Added to Fish config (~/.config/fish/config.fish)"; \
		else \
			echo "ℹ  PATH already configured in Fish"; \
		fi; \
	elif [ -f "$$HOME/.zshrc" ]; then \
		if ! grep -q "$$HOME/.local/bin" "$$HOME/.zshrc"; then \
			echo "" >> "$$HOME/.zshrc"; \
			echo "# Added by tfgrid-compose" >> "$$HOME/.zshrc"; \
			echo 'export PATH="$$HOME/.local/bin:$$PATH"' >> "$$HOME/.zshrc"; \
			echo "✅ Added to Zsh config (~/.zshrc)"; \
		else \
			echo "ℹ  PATH already configured in Zsh"; \
		fi; \
	elif [ -f "$$HOME/.bashrc" ]; then \
		if ! grep -q "$$HOME/.local/bin" "$$HOME/.bashrc"; then \
			echo "" >> "$$HOME/.bashrc"; \
			echo "# Added by tfgrid-compose" >> "$$HOME/.bashrc"; \
			echo 'export PATH="$$HOME/.local/bin:$$PATH"' >> "$$HOME/.bashrc"; \
			echo "✅ Added to Bash config (~/.bashrc)"; \
		else \
			echo "ℹ  PATH already configured in Bash"; \
		fi; \
	else \
		echo "⚠️  Could not detect shell config file"; \
		echo "💡 Manually add to your PATH:"; \
		echo "  Fish: set -x PATH \$$HOME/.local/bin \$$PATH"; \
		echo "  Bash/Zsh: export PATH=\"\$$HOME/.local/bin:\$$PATH\""; \
	fi
	@echo ""
	@echo "✅ Installation complete!"
	@echo ""
	@echo "💡 You can now use either command:"
	@echo "   • tfgrid-compose  (full name)"
	@echo "   • tfgrid          (shortcut)"
	@echo ""
	@echo "To create a custom shortcut: tfgrid-compose shortcut <name>"
	@echo ""
	@echo "🔄 Reload your shell or run: source ~/.bashrc (or ~/.zshrc or ~/.config/fish/config.fish)"
	@echo "🧪 Test with: tfgrid --version"

# Uninstall tfgrid-compose
uninstall:
	@echo "🗑️  Uninstalling tfgrid-compose..."
	@if [ -f "$$HOME/.local/bin/tfgrid-compose" ]; then \
		rm "$$HOME/.local/bin/tfgrid-compose"; \
		echo "✅ Removed ~/.local/bin/tfgrid-compose"; \
	fi
	@echo "🔗 Removing shortcuts..."
	@for link in $$HOME/.local/bin/*; do \
		if [ -L "$$link" ] && [ "$$(readlink "$$link")" = "$$HOME/.local/bin/tfgrid-compose" ]; then \
			rm "$$link"; \
			echo "✅ Removed shortcut: $$(basename $$link)"; \
		fi \
	done
	@if [ -d "$$HOME/.local/share/tfgrid-compose" ]; then \
		rm -rf "$$HOME/.local/share/tfgrid-compose"; \
		echo "✅ Removed ~/.local/share/tfgrid-compose"; \
	fi
	@echo "✅ Uninstall complete"

# Clean state
clean:
	./cli/tfgrid-compose clean

# Show logs
logs:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		echo "Usage: make logs APP=../tfgrid-ai-agent"; \
		exit 1; \
	fi
	./cli/tfgrid-compose logs $(APP)

# Check status
status:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		echo "Usage: make status APP=../tfgrid-ai-agent"; \
		exit 1; \
	fi
	./cli/tfgrid-compose status $(APP)

# SSH into deployment
ssh:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		echo "Usage: make ssh APP=../tfgrid-ai-agent"; \
		exit 1; \
	fi
	./cli/tfgrid-compose ssh $(APP)

# Quick connect to VM as developer user (uses context)
connect:
	@VM_IP=$$(cat .tfgrid-compose/state.yaml 2>/dev/null | grep '^vm_ip:' | awk '{print $$2}'); \
	if [ -z "$$VM_IP" ]; then \
		echo "❌ No deployment found. Run 'make up' first."; \
		exit 1; \
	fi; \
	echo "🔌 Connecting to VM as developer user..."; \
	ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
		root@$$VM_IP "su - developer"

# Test connectivity to VM
ping:
	@VM_IP=$$(cat .tfgrid-compose/state.yaml 2>/dev/null | grep '^vm_ip:' | awk '{print $$2}'); \
	if [ -z "$$VM_IP" ]; then \
		echo "❌ No deployment found. Run 'make up' first."; \
		exit 1; \
	fi; \
	echo "🏓 Testing connectivity to VM..."; \
	echo "IP: $$VM_IP"; \
	echo ""; \
	if ping -c 3 -W 2 $$VM_IP >/dev/null 2>&1; then \
		echo "✅ VM is reachable"; \
	else \
		echo "❌ Cannot reach VM"; \
		echo ""; \
		echo "Troubleshooting:"; \
		echo "  1. Check WireGuard: ip link show wg-ai-agent"; \
		echo "  2. Verify routes: ip route | grep wg-ai-agent"; \
		echo "  3. Try SSH: make ssh"; \
		exit 1; \
	fi

# Verify deployment health
verify:
	@VM_IP=$$(cat .tfgrid-compose/state.yaml 2>/dev/null | grep '^vm_ip:' | awk '{print $$2}'); \
	if [ -z "$$VM_IP" ]; then \
		echo "❌ No deployment found. Run 'make up' first."; \
		exit 1; \
	fi; \
	echo "🔍 Verifying deployment..."; \
	echo ""; \
	echo "📡 Testing connectivity..."; \
	if ping -c 1 -W 2 $$VM_IP >/dev/null 2>&1; then \
		echo "  ✅ Network connectivity OK"; \
	else \
		echo "  ❌ Network connectivity FAILED"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "🔐 Testing SSH access..."; \
	if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
		root@$$VM_IP "echo 'SSH OK'" >/dev/null 2>&1; then \
		echo "  ✅ SSH access OK"; \
	else \
		echo "  ❌ SSH access FAILED"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "👤 Checking developer user..."; \
	if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
		root@$$VM_IP "id developer" >/dev/null 2>&1; then \
		echo "  ✅ Developer user exists"; \
	else \
		echo "  ❌ Developer user NOT found"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "📁 Checking workspace..."; \
	if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
		root@$$VM_IP "test -d /home/developer/code" >/dev/null 2>&1; then \
		echo "  ✅ Workspace exists: /home/developer/code"; \
	else \
		echo "  ❌ Workspace NOT found"; \
		exit 1; \
	fi; \
	echo ""; \
	echo "✅ All checks passed! Deployment is healthy."

# Show addresses
address:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		echo "Usage: make address APP=../tfgrid-ai-agent"; \
		exit 1; \
	fi
	./cli/tfgrid-compose address $(APP)

# List patterns
patterns:
	./cli/tfgrid-compose patterns

# Full deployment test
test:
	@echo "🧪 Running full deployment test..."
	@echo ""
	@if [ -z "$(APP)" ]; then \
		echo "Using default app: ../tfgrid-ai-agent"; \
		APP=../tfgrid-ai-agent; \
	fi
	@echo "1. Cleaning previous state..."
	@$(MAKE) clean || true
	@echo ""
	@echo "2. Initializing configuration..."
	@$(MAKE) init APP=$(APP) || exit 1
	@echo ""
	@echo "3. Deploying application..."
	@$(MAKE) up APP=$(APP) || exit 1
	@echo ""
	@echo "4. Checking status..."
	@$(MAKE) status APP=$(APP) || true
	@echo ""
	@echo "✅ Test complete!"
	@echo ""
	@echo "To destroy: make down APP=$(APP)"

# Verify CLI installation
verify-cli:
	@echo "🔍 Verifying tfgrid-compose installation..."
	@./cli/tfgrid-compose help
	@echo ""
	@echo "✅ CLI is working!"
	@echo ""
	@echo "Available patterns:"
	@./cli/tfgrid-compose patterns

# Individual task commands (for debugging and iteration)

# Run Terraform only
terraform:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		echo "Usage: make terraform APP=../tfgrid-ai-agent"; \
		exit 1; \
	fi
	@export STATE_DIR=".tfgrid-compose" && bash core/tasks/terraform.sh

# Setup WireGuard only (reads app name from state file)
wireguard:
	@export STATE_DIR=".tfgrid-compose" && bash core/tasks/wireguard.sh

# Alias for wireguard
wg: wireguard

# Wait for SSH only (reads from state file)
wait-ssh:
	@export STATE_DIR=".tfgrid-compose" && bash core/wait-ssh.sh

# Generate inventory only (reads from state file)
inventory:
	@export STATE_DIR=".tfgrid-compose" && bash core/tasks/inventory.sh

# Run Ansible only (reads from state file)
ansible:
	@export STATE_DIR=".tfgrid-compose" && bash core/tasks/ansible.sh

# Execute command on deployed VM
exec:
	@if [ -z "$(APP)" ]; then \
		echo "Error: APP not specified"; \
		echo "Usage: make exec APP=../tfgrid-ai-agent CMD='command'"; \
		echo "Or set: export APP=../tfgrid-ai-agent"; \
		exit 1; \
	fi
	@if [ -z "$(CMD)" ]; then \
		echo "Error: CMD not specified"; \
		echo "Usage: make exec APP=../tfgrid-ai-agent CMD='login'"; \
		exit 1; \
	fi
	./cli/tfgrid-compose exec $(APP) $(CMD)

# ============================================
# AI Agent Convenience Commands
# ============================================

# Login to Qwen (automated OAuth with expect)
login:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		echo "Set: export APP=../tfgrid-ai-agent"; \
		exit 1; \
	fi
	@bash scripts/qwen-login.sh

# Create AI agent project (interactive)
create:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		exit 1; \
	fi
	@VM_IP=$$(cat .tfgrid-compose/state.yaml | grep '^vm_ip:' | awk '{print $$2}'); \
	if [ -z "$$VM_IP" ]; then \
		echo "❌ No deployment found. Run 'make up' first."; \
		exit 1; \
	fi; \
	if [ -z "$(project)" ]; then \
		echo "🚀 Starting interactive project creation..."; \
		echo ""; \
		ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
			root@$$VM_IP "su - developer -c 'cd /opt/ai-agent && /opt/ai-agent/scripts/create-project.sh'"; \
	else \
		echo "🚀 Creating project: $(project)"; \
		ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
			root@$$VM_IP "cd /opt/ai-agent/projects && mkdir -p $(project) && echo '✅ Project $(project) created! Run: make run project=$(project)'"; \
	fi

# Run AI agent project (interactive selection if no project specified)
run:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		exit 1; \
	fi
	@VM_IP=$$(cat .tfgrid-compose/state.yaml | grep '^vm_ip:' | awk '{print $$2}'); \
	if [ -z "$$VM_IP" ]; then \
		echo "❌ No deployment found. Run 'make up' first."; \
		exit 1; \
	fi; \
	if [ -z "$(project)" ]; then \
		echo "🚀 Starting AI agent (interactive project selection)..."; \
		echo ""; \
		ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
			root@$$VM_IP "su - developer -c 'cd /opt/ai-agent && bash scripts/interactive-wrapper.sh run'"; \
	else \
		./cli/tfgrid-compose exec $(APP) "su - developer -c '/opt/ai-agent/scripts/run-project.sh $(project)'"; \
	fi

# Monitor AI agent project (interactive selection if no project specified)
monitor:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		exit 1; \
	fi
	@VM_IP=$$(cat .tfgrid-compose/state.yaml | grep '^vm_ip:' | awk '{print $$2}'); \
	if [ -z "$$VM_IP" ]; then \
		echo "❌ No deployment found."; \
		exit 1; \
	fi; \
	if [ -z "$(project)" ]; then \
		echo "👁️  Monitor AI agent (interactive project selection)..."; \
		echo ""; \
		ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
			root@$$VM_IP "su - developer -c 'cd /opt/ai-agent && bash scripts/interactive-wrapper.sh monitor'"; \
	else \
		./cli/tfgrid-compose exec $(APP) "su - developer -c '/opt/ai-agent/scripts/monitor-project.sh $(project)'"; \
	fi

# Stop AI agent project (interactive selection if no project specified)
stop:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		exit 1; \
	fi
	@VM_IP=$$(cat .tfgrid-compose/state.yaml | grep '^vm_ip:' | awk '{print $$2}'); \
	if [ -z "$$VM_IP" ]; then \
		echo "❌ No deployment found."; \
		exit 1; \
	fi; \
	if [ -z "$(project)" ]; then \
		echo "⛔ Stop AI agent (interactive project selection)..."; \
		echo ""; \
		ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
			root@$$VM_IP "su - developer -c 'cd /opt/ai-agent && bash scripts/interactive-wrapper.sh stop'"; \
	else \
		./cli/tfgrid-compose exec $(APP) "su - developer -c '/opt/ai-agent/scripts/stop-project.sh $(project)'"; \
	fi

# List all projects  
list:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		exit 1; \
	fi
	./cli/tfgrid-compose exec $(APP) "su - developer -c '/opt/ai-agent/scripts/status-projects.sh'"

# Show project status (alias for list)
projects: list

# Show comprehensive status (service + projects)
allstatus:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		exit 1; \
	fi
	@echo "📊 TFGrid Compose Status"
	@echo "════════════════════════════════════════"
	@echo ""
	@echo "🔧 Service Status:"
	@./cli/tfgrid-compose status $(APP) | tail -n +8
	@echo ""
	@echo "🤖 AI Agent Projects:"
	@./cli/tfgrid-compose exec $(APP) "/opt/ai-agent/scripts/status-projects.sh"

# Remove project
remove:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		exit 1; \
	fi
	@if [ -z "$(project)" ]; then \
		./cli/tfgrid-compose exec $(APP) /opt/ai-agent/scripts/remove-project.sh; \
	else \
		./cli/tfgrid-compose exec $(APP) "/opt/ai-agent/scripts/remove-project.sh $(project)"; \
	fi
