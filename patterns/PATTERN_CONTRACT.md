# Pattern Contract

**All deployment patterns MUST follow this contract to work with tfgrid-compose orchestrator.**

## Required Outputs

Every pattern's Terraform configuration MUST provide these outputs:

### `primary_ip` (string, required)
The main IP address for connecting to the deployment. This is used for SSH and management.

```terraform
output "primary_ip" {
  value       = "10.1.3.2"  # or whatever the IP is
  description = "Primary IP address for SSH connection"
}
```

### `primary_ip_type` (string, required)
The type of the primary IP. Valid values: `wireguard`, `public`, `mycelium`

```terraform
output "primary_ip_type" {
  value       = "wireguard"
  description = "Type of primary IP"
}
```

### `deployment_name` (string, required)
The name of the deployment on TFGrid.

```terraform
output "deployment_name" {
  value       = "my_deployment"
  description = "Name of the deployment"
}
```

### `node_ids` (list, required)
List of node IDs used in this deployment.

```terraform
output "node_ids" {
  value       = [8, 12, 15]  # Single or multiple nodes
  description = "List of node IDs used in deployment"
}
```

---

## Optional Outputs

### `secondary_ips` (list, optional)
Additional IP addresses for multi-node deployments (workers, backends, etc.)

```terraform
output "secondary_ips" {
  value = [
    {
      name = "worker-1"
      ip   = "10.1.3.3"
      type = "wireguard"
      role = "worker"
    },
    {
      name = "worker-2"
      ip   = "10.1.3.4"
      type = "wireguard"
      role = "worker"
    }
  ]
  description = "Additional IPs for multi-node deployments"
}
```

### `mycelium_ip` (string, optional)
Mycelium IPv6 address if available.

```terraform
output "mycelium_ip" {
  value       = "57e:efab:75c4:1a3a:ff0f:2ac:d184:9715"
  description = "Mycelium IPv6 address"
}
```

### `connection_info` (map, optional)
Special connection information for non-standard deployments.

```terraform
output "connection_info" {
  value = {
    method     = "kubectl"      # How to connect: ssh, kubectl, etc.
    kubeconfig = "..."          # Config file content if needed
    endpoint   = "https://..."  # API endpoint
  }
  description = "Connection information"
}
```

---

## Pattern Examples

### Single-VM Pattern
```terraform
output "primary_ip" {
  value = split("/", grid_deployment.vm.vms[0].computedip)[0]
}

output "primary_ip_type" {
  value = "wireguard"
}

output "deployment_name" {
  value = grid_deployment.vm.name
}

output "node_ids" {
  value = [var.node_id]
}
```

### Gateway Pattern
```terraform
output "primary_ip" {
  value = grid_deployment.gateway.vms[0].public_ip
}

output "primary_ip_type" {
  value = "public"
}

output "secondary_ips" {
  value = [
    for vm in grid_deployment.backends.vms : {
      name = vm.name
      ip   = split("/", vm.computedip)[0]
      type = "wireguard"
      role = "backend"
    }
  ]
}

output "node_ids" {
  value = concat([var.gateway_node], var.backend_nodes)
}
```

### K3s Pattern
```terraform
output "primary_ip" {
  value = grid_deployment.k3s.vms[0].computedip  # master
}

output "primary_ip_type" {
  value = "wireguard"
}

output "secondary_ips" {
  value = [
    for vm in slice(grid_deployment.k3s.vms, 1, length(grid_deployment.k3s.vms)) : {
      name = vm.name
      ip   = vm.computedip
      type = "wireguard"
      role = "worker"
    }
  ]
}

output "connection_info" {
  value = {
    method     = "kubectl"
    kubeconfig = data.remote_file.kubeconfig.content
    endpoint   = "https://${primary_ip}:6443"
  }
}
```

---

## Why This Contract?

**Universal Orchestration**: The orchestrator never needs to know pattern-specific details. It just reads standard outputs.

**Future-Proof**: New patterns automatically work with the orchestrator.

**Multi-Node Support**: Secondary IPs handle gateway backends, k8s workers, database replicas, etc.

**Flexibility**: Optional outputs allow pattern-specific features without breaking compatibility.

---

## Validation

The orchestrator will **fail** deployment if `primary_ip` is not provided. All other standard outputs have sensible defaults.

Test your pattern:
```bash
cd patterns/my-pattern/infrastructure
terraform output primary_ip        # MUST return an IP
terraform output primary_ip_type   # MUST return wireguard/public/mycelium
terraform output deployment_name   # MUST return a name
terraform output node_ids          # MUST return JSON array
```
