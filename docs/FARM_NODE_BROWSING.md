# Farm Node Browsing

Browse and filter nodes by farm name using the enhanced `tfgrid-compose nodes --farm` command.

## Overview

The farm node browsing feature allows you to view all nodes within a specific farm, showing their online/offline status, specifications, and performance metrics in real-time using GridProxy API.

## Usage

### Basic Farm Browsing

```bash
# Show all nodes in a specific farm
tfgrid-compose nodes --farm=farm-name

# Alternative syntax using subcommand
tfgrid-compose nodes farm <farm-name>
```

### Examples

```bash
# Browse nodes from freefarm
t nodes --farm=freefarm

# Browse nodes from lin farm
t nodes --farm=lin

# Case-insensitive matching (all work the same)
t nodes --farm=qualiafarm
t nodes --farm=QualiaFarm
t nodes --farm=QUALIAFARM
```

## Output Format

The command displays a comprehensive farm overview:

```
🏢 Farm: freefarm
📊 Total Nodes: 22
🟢 Online: 9
🔴 Offline: 13

🔍 ThreeFold Node Browser

ID     Farm                 Location        CPU    RAM    Disk   IPv4   Load     Uptime    
────────────────────────────────────────────────────────────────────────────────
11🟢 Freefarm             Belgium         8      15G    Yes    62%    682d     
24🟢 Freefarm             Belgium         8      15G    Yes    75%    599d     
8🔴  Freefarm             Belgium         56     188G   Yes    33%    213d     
...
```

### Data Displayed

- **ID**: Node ID number
- **Farm**: Farm name
- **Location**: Country (and city if available)
- **CPU**: Total CPU cores
- **RAM**: Total RAM in GB
- **Disk**: Total disk in TB  
- **IPv4**: IPv4 availability (Yes/No)
- **Load**: CPU usage percentage
- **Uptime**: Days since last restart

### Status Indicators

- 🟢 **Green indicator**: Node is online and healthy
- 🔴 **Red indicator**: Node is offline or unhealthy

## Features

### Real-Time Data
- Fetches live data from GridProxy API
- Shows current node status and resource usage
- Automatically updates farm cache every hour

### Case-Insensitive Matching
- Farm names are matched case-insensitively
- Works with any capitalization of farm names
- Supports both farm names and farm IDs

### Performance Metrics
- CPU usage percentage
- RAM and disk utilization
- Network configuration (IPv4 availability)
- System uptime
- Online/offline status

### Error Handling
- Validates farm existence before querying
- Provides helpful error messages for invalid farms
- Suggests alternatives when farm not found

## Integration with Shortcuts

Works seamlessly with shortcut aliases:

```bash
# Create shortcut
t shortcut t

# Use farm browsing with shortcut
t nodes --farm=freefarm
t farm lin
```

## Technical Details

### API Integration
- Uses ThreeFold GridProxy API
- Endpoint: `https://gridproxy.grid.tf/nodes`
- Supports farm filtering with case-insensitive matching

### Farm Caching
- Farms are cached locally for 1 hour
- Cache location: `~/.config/tfgrid-compose/farm-cache.json`
- Auto-updates when cache expires

### Filtering Logic
1. Fetch all nodes from GridProxy
2. Filter by farm name (case-insensitive)
3. Sort by status (online first) then uptime
4. Display formatted table with statistics

## Troubleshooting

### Farm Not Found
```
❌ Farm 'invalid-farm' not found
ℹ Run 'tfgrid-compose nodes' to browse all available nodes
```

**Solutions:**
- Check farm name spelling
- Try different capitalization
- Use `tfgrid-compose nodes` to browse all farms
- Verify farm exists on ThreeFold Grid dashboard

### No Nodes in Farm
```
❌ No nodes found in farm 'empty-farm'
```

**Possible causes:**
- Farm has no active nodes
- Farm is offline or decommissioned
- Temporary GridProxy API issues

### API Connection Issues
```
❌ Failed to fetch nodes from GridProxy
```

**Solutions:**
- Check internet connection
- Verify GridProxy API accessibility
- Try again in a few minutes

## Related Commands

- `tfgrid-compose nodes` - Interactive node browser
- `tfgrid-compose nodes favorites` - Show favorite nodes
- `tfgrid-compose nodes show <id>` - View node details
- `tfgrid-compose nodes favorite add <id>` - Add to favorites

## See Also

- [Node Selection Guide](NODE_SELECTION.md)
- [Deployment Options](../README.md#deployment-options)
- [ThreeFold Grid Dashboard](https://dashboard.grid.tf)