# Minecraft Support Playbook

Audience: support and ops staff handling Minecraft incidents.

## Principle

- Diagnose first.
- Avoid destructive actions.
- Move files to quarantine instead of deleting.
- Confirm outcome after each change.

## Fast triage workflow

1. Check host health

```bash
./scripts/support/minecraft-node-diagnose.sh <host_ip> [ssh_port]
```

2. Validate panel/server details

```bash
PEXNODE_PANEL_URL=https://panel.pexnode.com \
PEXNODE_PTERO_APPLICATION_API_KEY=ptla_xxx \
./scripts/support/ptero-server-action.sh <server_id_or_uuid> details
```

3. Power-cycle if needed

```bash
# restart
./scripts/support/ptero-server-action.sh <server_ref> restart

# start
./scripts/support/ptero-server-action.sh <server_ref> start
```

4. Send diagnostic command

```bash
./scripts/support/ptero-server-action.sh <server_ref> command "say Running diagnostics"
```

5. If bad file suspected, quarantine it (non-destructive)

```bash
./scripts/support/quarantine-path.sh <host_ip> <absolute_path_on_host> [ssh_port]
```

## Common symptom paths

### Server not starting

Check:
- Wings service active
- Host memory/disk pressure
- Recent Wings logs
- Container status
- Panel reports and startup command

First actions:
1. restart server
2. check logs and startup params
3. quarantine suspicious plugin/mod/jar
4. retry start

### Crash loop after update

1. quarantine newest plugin/mod files
2. restart server
3. reintroduce changes one-by-one

### Out-of-memory

1. verify node memory pressure
2. verify server memory limits in panel
3. reduce plugin load or world view distance

## Safe file handling policy

- Never delete customer files during first-line support.
- Move to quarantine with timestamp path:
  - `/var/backups/pexnode-quarantine/<timestamp>/...`
- Document every moved path.

## Escalation

Escalate to engineering when:
- repeated crash loops after clean baseline
- corruption in world data
- recurring node-level instability
- panel/WHMCS state mismatch
