# Ansible Configuration for ThreeFold Grid Gateway

This directory contains Ansible playbooks and roles for configuring ThreeFold Grid gateway deployments.

## Directory Structure

```
platform/
├── site.yml              # Main playbook
├── test-gateway.yml      # Testing playbook
├── requirements.yml      # Ansible dependencies
├── inventory.ini         # Generated inventory (created by scripts)
├── group_vars/           # Group variables
│   ├── all.yml          # Global variables
│   ├── gateway.yml      # Gateway-specific variables
│   └── internal.yml     # Internal VM variables
└── roles/               # Ansible roles
    ├── gateway_common/  # Common gateway setup
    ├── gateway_nat/     # NAT-based gateway
    ├── gateway_proxy/   # Proxy-based gateway
    └── testing/         # Testing utilities
```

## Gateway Types

### NAT Gateway (`gateway_nat`)
- Uses nftables for network address translation
- Supports port forwarding and masquerading
- Lightweight and high-performance
- Best for simple routing scenarios

### Proxy Gateway (`gateway_proxy`)
- Uses HAProxy for TCP/UDP load balancing
- Uses Nginx for HTTP/HTTPS reverse proxy
- Supports SSL termination and advanced routing
- Best for application-level features

## Usage

### 1. Generate Inventory
```bash
make inventory
```

### 2. Choose Gateway Type
```bash
# NAT gateway (default)
export GATEWAY_TYPE=gateway_nat

# Proxy gateway
export GATEWAY_TYPE=gateway_proxy
```

### 3. Run Configuration
```bash
make ansible
```

### 4. Test Configuration
```bash
make ansible-test
```

## Configuration Variables

### Gateway Variables (`group_vars/gateway.yml`)
```yaml
# Gateway type
gateway_type: gateway_nat

# Port forwarding (NAT only)
port_forwards:
  - port: 8080
    target_ip: 10.1.0.10
    target_port: 80

# Proxy configuration (proxy only)
proxy_ports: [8080, 8443]
udp_ports: []
enable_ssl: false
domain_name: "example.com"
ssl_email: "admin@example.com"

# Testing
enable_testing: false
```

### Internal VM Variables (`group_vars/internal.yml`)
```yaml
# Services to deploy
services:
  - name: web
    port: 80
    type: http
  - name: api
    port: 8080
    type: tcp
```

## Manual Execution

### Run specific playbooks:
```bash
# Main configuration
ansible-playbook -i inventory.ini site.yml

# Testing
ansible-playbook -i inventory.ini test-gateway.yml

# Specific roles
ansible-playbook -i inventory.ini site.yml --tags gateway_common
```

### Run on specific hosts:
```bash
# Only gateway
ansible-playbook -i inventory.ini site.yml --limit gateway

# Only internal VMs
ansible-playbook -i inventory.ini site.yml --limit internal
```

## Custom Gateway Types

To create a custom gateway type:

1. Create a new role: `platform/roles/gateway_custom/`
2. Add tasks in: `platform/roles/gateway_custom/tasks/main.yml`
3. Add handlers in: `platform/roles/gateway_custom/handlers/main.yml`
4. Add templates in: `platform/roles/gateway_custom/templates/`
5. Update `site.yml` to include the new role
6. Set `GATEWAY_TYPE=gateway_custom`

## Troubleshooting

### Common Issues

1. **SSH Connection Failed**
   ```bash
   # Check SSH connectivity
   ansible -i inventory.ini gateway -m ping

   # Debug SSH
   ansible -i inventory.ini gateway -m ping -vvv
   ```

2. **Firewall Rules Not Applied**
   ```bash
   # Check nftables rules
   ansible -i inventory.ini gateway -m command -a "nft list ruleset"

   # Reload firewall
   ansible -i inventory.ini gateway -m systemd -a "name=nftables state=reloaded"
   ```

3. **Services Not Starting**
   ```bash
   # Check service status
   ansible -i inventory.ini gateway -m systemd -a "name=haproxy state=started"

   # View service logs
   ansible -i inventory.ini gateway -m command -a "journalctl -u haproxy -n 50"
   ```

### Debug Mode
```bash
# Run with verbose output
ansible-playbook -i inventory.ini site.yml -vvv

# Run with debug
ansible-playbook -i inventory.ini site.yml -vvvv
```

## Extending the Configuration

### Adding New Services
1. Create a new role for the service
2. Add it to the appropriate host group in `site.yml`
3. Configure variables in `group_vars/`

### Adding New Gateway Features
1. Extend existing roles with new tasks
2. Add new variables to `group_vars/gateway.yml`
3. Create new templates for configuration files

### Testing New Configurations
1. Use the `testing` role for validation
2. Add custom tests to `test-gateway.yml`
3. Run tests with `make ansible-test`