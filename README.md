# Pexnode Monitoring

Centralized Netdata monitoring for Pexnode platform hosts and containers.

Plus: Complete Wings node provisioning with security hardening.

## Quick Start

### Monitoring Setup (5 min)

See [docs/QUICK-START.md](docs/QUICK-START.md) for full setup.

### Provision New Wings Node (5-10 min)

```bash
# From this repo, deploy everything to a target host IP:
PANEL_URL=https://panel.pexnode.com \
WINGS_API_KEY=ptla_xxxxxxxxxxxxx \
NETDATA_TOKEN=your_netdata_token \
./scripts/deploy-wing-host.sh 10.20.0.11 11 2222
```

This will:
- Install Wings daemon
- Register with Pterodactyl panel
- Enroll in monitoring
- Harden security (firewall, SSH, kernel)

See [docs/WINGS-PROVISIONING.md](docs/WINGS-PROVISIONING.md) for details.

## Architecture

```
Azure Container (Parent)
├── Netdata dashboard :19999
├── Alert engine
└── Metrics collector

    ↓ (secure TLS tunnel)

Pterodactyl Host 74.50.65.10 (Child)
├── Netdata child agent
└── Wings containers (auto-monitored)

WHMCS Host 104.37.190.203 (Child)
└── Netdata child agent
```

## Alerts

- CPU > 80%
- RAM > 85%
- Disk > 90%
- Container restart loops
- Host unreachable

Delivered via: SMTP, Mobile app (push + sound), Webhooks

## MCP Integration

Hugo AI can query metrics and manage alerts via [mcp/monitoring-tools.md](mcp/monitoring-tools.md)

## Files

**Monitoring Setup:**
- `azure/docker-compose.yml` — Azure parent deployment
- `azure/.env.template` — Configuration template
- `scripts/enroll-host.sh` — Add new host to monitoring
- `scripts/auto-enroll-onboot.sh` — Systemd/cron auto-enrollment

**Wings Node Provisioning:**
- `scripts/deploy-wing-host.sh` — One-command remote deployment by host IP
- `scripts/provision-wings-node.sh` — Complete node setup (Wings + security + monitoring)
- `scripts/provision-wings-bootstrap.sh` — Cloud-init wrapper for automated provisioning
- `scripts/setup-host-maintenance.sh` — Installs recurring health/cleanup jobs on host
- `scripts/preflight-check.sh` — Operator preflight checks before deploy actions
- `scripts/support/minecraft-node-diagnose.sh` — Read-only node diagnostics for support
- `scripts/support/quarantine-path.sh` — Move suspicious files to quarantine (non-destructive)
- `scripts/support/ptero-server-action.sh` — Minecraft-safe start/stop/restart/command/reinstall actions
- `scripts/CLOUD-INIT-SETUP.md` — Cloud provider integration (Azure, AWS, etc.)

**Azure Automation:**
- `scripts/azure/bootstrap-service-principal.sh` — One-time least-scope SP bootstrap
- `scripts/azure/deploy-netdata-aci.sh` — Deploy low-cost Netdata parent in Azure ACI
- `scripts/azure/destroy-netdata-aci.sh` — Tear down Netdata ACI container

**Documentation:**
- `docs/QUICK-START.md` — 5-minute setup
- `docs/DEPLOYMENT-GUIDE.md` — Full monitoring deployment
- `docs/ALERT-RUNBOOK.md` — Alert configuration and notifications
- `docs/AUTO-ENROLLMENT.md` — Auto-enroll existing hosts
- `docs/WINGS-PROVISIONING.md` — New game node provisioning
- `docs/TROUBLESHOOTING.md` — Common issues and fixes
- `docs/MINECRAFT-SUPPORT-PLAYBOOK.md` — Support playbook for Minecraft incidents
- `mcp/` — MCP tool specifications for Hugo AI

**MCP Templates:**
- `mcp/MCP-OPERATIONS-SETUP.md` — Required tools and safety model
- `mcp/MINECRAFT-SUPPORT-ROADMAP.md` — Roadmap for deeper support workflows (logs/config/mods)
- `mcp/templates/pexnode-monitoring-mcp.env.example` — MCP env template
- `mcp/templates/mcp-tools-required.json` — Required tool catalog

## Requirements

- Parent: Docker, 512MB–1GB RAM, Azure Container Instances
- Children: Docker 20.10+, SSH access, 50MB RAM per child
- Wings nodes: Bare Ubuntu 22.04 LTS, root access, 2GB+ RAM

## Setup Paths

**New to monitoring?** Start here: [docs/COMPLETE-SETUP.md](docs/COMPLETE-SETUP.md)

**Just monitoring existing hosts?** [docs/QUICK-START.md](docs/QUICK-START.md)

**Provisioning Wings nodes?** [docs/WINGS-PROVISIONING.md](docs/WINGS-PROVISIONING.md)

**Deploying to cloud (Azure, AWS)?** [scripts/CLOUD-INIT-SETUP.md](scripts/CLOUD-INIT-SETUP.md)
