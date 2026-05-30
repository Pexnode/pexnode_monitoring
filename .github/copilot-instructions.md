# GitHub Copilot Instructions (pexnode_monitoring)

This is the monitoring/observability repository for Pexnode platform.

## Core Mission

Provide lightweight, cloud-independent monitoring for all Pexnode hosts and game containers.

## Architecture

- **Parent**: Netdata container running on Azure Container Instances
- **Children**: Netdata agents on Pterodactyl (74.50.65.10) and WHMCS (104.37.190.203) hosts
- **Dashboard**: Netdata Cloud web interface + mobile app
- **Alerts**: Email, push notifications, webhooks

## Key Files

- `azure/docker-compose.yml` — Parent deployment
- `scripts/enroll-host.sh` — Add host to monitoring
- `docs/DEPLOYMENT-GUIDE.md` — Full setup walkthrough
- `docs/ALERT-RUNBOOK.md` — Alert configuration and notifications
- `docs/AUTO-ENROLLMENT.md` — Auto-enroll new servers
- `mcp/monitoring-tools.md` — MCP tool specifications for Hugo AI

## Workflow

1. Deploy parent on Azure: `cd azure && docker-compose up -d`
2. Enroll hosts: `./scripts/enroll-host.sh <ip> <token>`
3. Configure alerts: See ALERT-RUNBOOK.md
4. New servers: Include auto-enrollment script in boot sequence

## Integration with Pexnode Ops

Cross-references:
- Ops repo: `/home/hakon/git/pexnode_ops_agent/docs/50-MCP/`
- MCP tools will be added to pexnode_mcp server for Hugo AI integration
- Alert thresholds and runbooks linked from ops repo

## Do Not

- Commit secrets (Netdata tokens, SMTP passwords, etc.)
- Modify Azure resources directly via portal (always git → deploy)
- Add monitoring for systems outside Pexnode topology
