# Pexnode Monitoring

Centralized Netdata monitoring for Pexnode platform hosts and containers.

Plus: Complete Wings node provisioning with security hardening.

## Quick Start

### Monitoring Setup (5 min)

See [docs/QUICK-START.md](docs/QUICK-START.md) for full setup.

### Provision New Wings Node (5-10 min)

```bash
# Get API key from panel: Admin → API → Application Keys
./scripts/provision-wings-node.sh \
  https://panel.pexnode.com \
  1 \
  ptla_xxxxxxxxxxxxx \
  your_netdata_token \
  2222
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
- `scripts/provision-wings-node.sh` — Complete node setup (Wings + security + monitoring)
- `scripts/provision-wings-bootstrap.sh` — Cloud-init wrapper for automated provisioning
- `scripts/CLOUD-INIT-SETUP.md` — Cloud provider integration (Azure, AWS, etc.)

**Documentation:**
- `docs/QUICK-START.md` — 5-minute setup
- `docs/DEPLOYMENT-GUIDE.md` — Full monitoring deployment
- `docs/ALERT-RUNBOOK.md` — Alert configuration and notifications
- `docs/AUTO-ENROLLMENT.md` — Auto-enroll existing hosts
- `docs/WINGS-PROVISIONING.md` — New game node provisioning
- `docs/TROUBLESHOOTING.md` — Common issues and fixes
- `mcp/` — MCP tool specifications for Hugo AI

## Requirements

- Parent: Docker, 512MB–1GB RAM, Azure Container Instances
- Children: Docker 20.10+, SSH access, 50MB RAM per child
- Wings nodes: Bare Ubuntu 22.04 LTS, root access, 2GB+ RAM

## Setup Paths

**New to monitoring?** Start here: [docs/COMPLETE-SETUP.md](docs/COMPLETE-SETUP.md)

**Just monitoring existing hosts?** [docs/QUICK-START.md](docs/QUICK-START.md)

**Provisioning Wings nodes?** [docs/WINGS-PROVISIONING.md](docs/WINGS-PROVISIONING.md)

**Deploying to cloud (Azure, AWS)?** [scripts/CLOUD-INIT-SETUP.md](scripts/CLOUD-INIT-SETUP.md)
