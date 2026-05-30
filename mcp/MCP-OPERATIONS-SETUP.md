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

5. Support file workflows (safe)
- list files
- read file content
- move file to quarantine (no hard delete by default)
- restore from quarantine

6. Config adjustments
- controlled config patch tool with allowlist (server.properties, paper.yml, spigot.yml, bukkit.yml)
- rollback snapshot before write

7. Mods/plugins management roadmap
- phase 1: upload/update by signed URL + checksum validation
- phase 2: compatibility checks against server version and loader type
- phase 3: policy engine for approved plugin/mod sources

## Safety model

- Write tools must be gated by `MCP_ENABLE_WRITES=true`
- Restrict write actions to Minecraft product identifiers
- Require explicit server match before write action
- Keep WHMCS writes disabled in MCP
- Require quarantine move for risky file changes before destructive actions
- Prefer patch/update tools over direct overwrite

## Files

- templates/pexnode-monitoring-mcp.env.example
- templates/mcp-tools-required.json
- MINECRAFT-SUPPORT-ROADMAP.md
- MCP-IMPLEMENTATION-CHECKLIST.md

## Implementation target

Apply these templates to your active MCP server repository and validate tools before enabling writes.
