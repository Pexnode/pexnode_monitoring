# Deploy Script Runbook

Primary script: `scripts/deploy-wing-host.sh`

Preflight script: `scripts/preflight-check.sh`

## What it does

1. Validates required env vars and arguments.
2. Acquires a local host-specific lock (`.locks/deploy-<ip>.lock`).
3. Verifies SSH connectivity with retries.
4. Uploads provisioning + maintenance scripts to target host.
5. Acquires a remote lock (`/var/lock/pexnode-wings-provision.lock`).
6. Runs full provisioning (Wings + panel config + monitoring + hardening).
7. Installs recurring maintenance jobs.

## Required env vars

- `PANEL_URL`
- `WINGS_API_KEY`

Optional env vars:
- `NETDATA_TOKEN`
- `DEPLOY_SSH_USER` (default `root`)
- `DEPLOY_SSH_KEY`
- `DEPLOY_SSH_OPTIONS`
- `REMOTE_SSH_PORT` (default `22`)

## Example

```bash
./scripts/preflight-check.sh

PANEL_URL=https://panel.pexnode.com \
WINGS_API_KEY=ptla_xxxxx \
NETDATA_TOKEN=claim_xxxxx \
./scripts/deploy-wing-host.sh 10.20.0.11 11 2222
```

Dry run:

```bash
DRY_RUN=true PANEL_URL=https://panel.pexnode.com WINGS_API_KEY=ptla_xxxxx \
./scripts/deploy-wing-host.sh 10.20.0.11 11 2222
```

## Re-run behavior

Safe to re-run:
- Existing Wings binary/service/config are compared and updated only when changed.
- Existing netdata-child container is reused or started if already created.
- SSH/firewall/fail2ban/sysctl hardening is applied idempotently.
- Maintenance cron is overwritten deterministically, not duplicated.

## Failure behavior

- Script exits on first hard failure with non-zero code.
- Locking prevents race conditions from concurrent runs.
- Remote provision step aborts if lock already in use.

## Post-run checks

- `systemctl status wings`
- `docker ps | grep netdata-child`
- `ufw status`
- Panel node status is online
- Node appears in Netdata
