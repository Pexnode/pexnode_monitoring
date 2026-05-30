# MCP Implementation Checklist (When Server Repo Is Ready)

Use this checklist to wire MCP quickly once your MCP repository is available.

## 1. Environment

- [ ] copy `mcp/templates/pexnode-monitoring-mcp.env.example`
- [ ] set `PEXNODE_PANEL_URL`
- [ ] set `PEXNODE_PTERO_APPLICATION_API_KEY`
- [ ] set `WHMCS_API_URL`, `WHMCS_API_IDENTIFIER`, `WHMCS_API_SECRET`
- [ ] set `NETDATA_BASE_URL`
- [ ] keep `MCP_ENABLE_WRITES=false` initially
- [ ] set `MCP_ALLOWED_GAMES=minecraft`

## 2. Required tool registration

Implement and register all tools in:
- `mcp/templates/mcp-tools-required.json`

Minimum write tools:
- `ptero.server_power`
- `ptero.send_server_command`
- `ptero.reinstall_server`

Minimum support tools:
- `ptero.tail_latest_log`
- `ptero.search_logs`
- `ptero.move_file_to_quarantine`
- `ptero.restore_quarantined_file`
- `ptero.patch_config_file`

## 3. Preferred install endpoints

Use application API endpoints added in panel:
- `POST /api/application/servers/{server_id}/minecraft/plugins/install`
- `POST /api/application/servers/{server_id}/bedrock/addons/install`

## 4. Safety gates

- [ ] reject write operations if `MCP_ENABLE_WRITES != true`
- [ ] reject non-minecraft write targets
- [ ] require quarantine-first for risky file operations
- [ ] require checksum for artifact installs
- [ ] keep WHMCS operations read-only

## 5. Validation

- [ ] tool health check endpoint passes
- [ ] read-only tools pass smoke test
- [ ] write tools tested on non-production/staging server
- [ ] `docs/30-Runbooks/Smoke-Tests-Minecraft-Support.md` passes

## 6. Go-live

- [ ] enable `MCP_ENABLE_WRITES=true` in controlled environment
- [ ] announce available actions to support team
- [ ] monitor logs + alerting for first 72 hours
