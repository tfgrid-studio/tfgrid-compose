# Registry Workflow Example

This example demonstrates the new v0.10.0 registry integration features.

## Browse Available Apps

```bash
# Search all apps in registry
tfgrid-compose search

# Search for specific app
tfgrid-compose search wordpress

# Search by tag
tfgrid-compose search --tag=cms
```

## Deploy Apps by Name

```bash
# Deploy WordPress from registry
tfgrid-compose up wordpress

# Deploy AI agent
tfgrid-compose up ai-agent

# Deploy Nextcloud
tfgrid-compose up nextcloud
```

## Manage Multiple Apps

```bash
# List all deployed apps
tfgrid-compose list
# Output:
#   * wordpress (active)
#     ai-agent
#     nextcloud

# Switch to ai-agent
tfgrid-compose switch ai-agent

# Now commands operate on ai-agent
tfgrid-compose logs        # Shows ai-agent logs
tfgrid-compose status      # Shows ai-agent status
tfgrid-compose exec login  # Runs command on ai-agent

# Switch back to wordpress
tfgrid-compose switch wordpress
tfgrid-compose logs        # Shows wordpress logs
```

## App Caching

Apps are automatically cached:

```
~/.config/tfgrid-compose/
├── registry/
│   └── apps.yaml           # Cached registry (1hr TTL)
├── apps/
│   ├── wordpress/          # Cached app repos
│   ├── ai-agent/
│   └── nextcloud/
├── state/
│   ├── wordpress/          # Per-app state
│   ├── ai-agent/
│   └── nextcloud/
└── current-app             # Active app pointer
```

## Workflow Comparison

### Old Way (v0.9.0):
```bash
git clone https://github.com/tfgrid-studio/tfgrid-ai-agent
cd tfgrid-ai-agent
tfgrid-compose init .
tfgrid-compose up .
```

### New Way (v0.10.0):
```bash
tfgrid-compose search
tfgrid-compose up ai-agent
```

## Deploy Multiple Apps

```bash
# Deploy dev, staging, and prod apps
tfgrid-compose up wordpress    # WordPress blog
tfgrid-compose up ai-agent     # AI development
tfgrid-compose up nextcloud    # File storage

# List all
tfgrid-compose list
#   * nextcloud (active)
#     ai-agent
#     wordpress

# Work with AI agent
tfgrid-compose switch ai-agent
tfgrid-compose exec create my-project
tfgrid-compose exec run my-project

# Check WordPress
tfgrid-compose switch wordpress
tfgrid-compose address  # Get WordPress URL

# Manage Nextcloud
tfgrid-compose switch nextcloud
tfgrid-compose logs
```

## Clean Up

```bash
# Destroy specific app
tfgrid-compose down wordpress

# Switch and destroy
tfgrid-compose switch ai-agent
tfgrid-compose down

# List remaining
tfgrid-compose list
```

## Mix Registry and Local Apps

```bash
# Deploy from registry
tfgrid-compose up wordpress

# Deploy from local path
tfgrid-compose up ./my-custom-app

# Both work the same way
tfgrid-compose list
#   * my-custom-app (active)
#     wordpress
```

## Notes

- **Registry cache**: Refreshed every hour automatically
- **App cache**: Downloaded once, reused for all deployments
- **State isolation**: Each app has independent state
- **Context switching**: Switch between apps instantly
- **Backward compatible**: Local paths still work perfectly
