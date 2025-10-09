.PHONY: help init up down clean logs status ssh address patterns test verify \
        terraform wireguard wg wait-ssh inventory ansible

# Default app (can be overridden by environment variable or command line)
APP ?=

# Default target
help:
	@echo "╔═══════════════════════════════════════════════════════════════╗"
	@echo "║  TFGrid Compose - Universal Deployment Orchestrator           ║"
	@echo "║  Status: ✅ Production Ready (v0.1.0-mvp)                     ║"
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
	@echo "  make patterns   - List deployment patterns"
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
	@echo "Installing tfgrid-compose..."
	@if [ ! -d "$$HOME/.local/bin" ]; then \
		mkdir -p "$$HOME/.local/bin"; \
		echo "Created ~/.local/bin"; \
	fi
	@cp cli/tfgrid-compose "$$HOME/.local/bin/tfgrid-compose"
	@chmod +x "$$HOME/.local/bin/tfgrid-compose"
	@echo "Installed to ~/.local/bin/tfgrid-compose"
	@echo ""
	@echo "Add to your PATH if not already:"
	@echo "  Fish: set -x PATH \$$HOME/.local/bin \$$PATH"
	@echo "  Bash: export PATH=\"\$$HOME/.local/bin:\$$PATH\""
	@echo ""
	@echo "Then run: tfgrid-compose --version"

# Uninstall tfgrid-compose
uninstall:
	@echo "Uninstalling tfgrid-compose..."
	@if [ -f "$$HOME/.local/bin/tfgrid-compose" ]; then \
		rm "$$HOME/.local/bin/tfgrid-compose"; \
		echo "Removed ~/.local/bin/tfgrid-compose"; \
	else \
		echo "tfgrid-compose not found in ~/.local/bin"; \
	fi

# Clean state
clean:
	./cli/tfgrid-compose clean

# Show logs
logs:
{{ ... }}
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

# Verify CLI
verify:
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
			root@$$VM_IP "cd /opt/ai-agent && /opt/ai-agent/scripts/create-project.sh"; \
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
			root@$$VM_IP "cd /opt/ai-agent && bash scripts/interactive-wrapper.sh run"; \
	else \
		./cli/tfgrid-compose exec $(APP) "/opt/ai-agent/scripts/run-project.sh $(project)"; \
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
			root@$$VM_IP "cd /opt/ai-agent && bash scripts/interactive-wrapper.sh monitor"; \
	else \
		./cli/tfgrid-compose exec $(APP) "/opt/ai-agent/scripts/monitor-project.sh $(project)"; \
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
			root@$$VM_IP "cd /opt/ai-agent && bash scripts/interactive-wrapper.sh stop"; \
	else \
		./cli/tfgrid-compose exec $(APP) "/opt/ai-agent/scripts/stop-project.sh $(project)"; \
	fi

# List all projects  
list:
	@if [ -z "$(APP)" ]; then \
		echo "❌ Error: APP not specified"; \
		exit 1; \
	fi
	./cli/tfgrid-compose exec $(APP) "/opt/ai-agent/scripts/status-projects.sh"

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
