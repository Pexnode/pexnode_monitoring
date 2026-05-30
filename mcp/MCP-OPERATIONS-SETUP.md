# MCP Operations Setup

This package prepares MCP integration requirements for monitoring + operations.

## Scope

This setup targets only Minecraft operations and includes:
- Monitoring queries and alert actions
- Pterodactyl power/control actions
- WHMCS customer/billing read actions
- Troubleshooting checklists

## Required tool groups

1. Monitoring (Netdata)
- get host metrics
- list and acknowledge alerts
- adjust alert thresholds

2. Pterodactyl (Minecraft-only)
- start/stop/restart/kill
- reinstall server
- send console command
- read server status/details

3. WHMCS
- client lookup
- services
- invoices

4. Troubleshooting
- run predefined checks for node health, panel API reachability, and billing linkage

## Safety model

- Write tools must be gated by `MCP_ENABLE_WRITES=true`
- Restrict write actions to Minecraft product identifiers
- Require explicit server match before write action
- Keep WHMCS writes disabled in MCP

## Files

- templates/pexnode-monitoring-mcp.env.example
- templates/mcp-tools-required.json

## Implementation target

Apply these templates to your active MCP server repository and validate tools before enabling writes.
