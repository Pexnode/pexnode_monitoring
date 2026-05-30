# MCP Minecraft Support Roadmap

## Current feasibility

Pterodactyl API supports:
- power actions (start/stop/restart/kill)
- console command send
- reinstall action
- file listing/read/write via client file endpoints (with signed URL flow)

WHMCS API supports:
- account/service/invoice context

## Gaps to implement in MCP server repo

1. File quarantine workflow (recommended first)
- tool: `ptero.move_file_to_quarantine`
- behavior: move, not delete
- target path convention: `/home/container/.quarantine/<timestamp>/...`

2. Config patch workflow
- tool: `ptero.patch_config_file`
- allowlist: `server.properties`, `paper.yml`, `spigot.yml`, `bukkit.yml`
- auto backup before patch
- include rollback operation id

3. Log diagnosis helpers
- tool: `ptero.tail_latest_log`
- tool: `ptero.search_logs`
- parse common Minecraft startup exceptions and map to action hints

4. Mods/plugins install workflow
- tool: `ptero.install_artifact`
- required inputs: URL, sha256, destination folder
- enforce source allowlist
- optional compatibility policy checks by version/loader

5. Safe restore workflow
- tool: `ptero.restore_quarantined_file`
- move file back from quarantine path

## Security model

- write tools gated by `MCP_ENABLE_WRITES=true`
- game gate: `MCP_ALLOWED_GAMES=minecraft`
- optional approval mode for reinstall and artifact install

## Why not delete-first

Support incidents often require rollback.
Quarantine-first preserves customer state and enables quick restore.
