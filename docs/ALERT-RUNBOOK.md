# Alert Runbook

All alerts route to Discord `#ops` via webhook (`DISCORD_WEBHOOK_OPS`).
The parent container on Azure evaluates alarms for itself and all streaming children.

---

## Alert Delivery

- **Channel**: Discord `#ops` (`DISCORD_WEBHOOK_OPS` in `.env`)
- **Configured in**: `health_alarm_notify.conf`, written at ACI startup by `scripts/azure/deploy-netdata-aci.sh`
- **All alert roles** (`sysadmin`, `webmaster`, etc.) route to the same `#ops` channel

Test the webhook manually:
```bash
curl -X POST -H "Content-Type: application/json" \
  -d '{"embeds":[{"title":"Test","description":"webhook delivery check","color":3066993}]}' \
  "$DISCORD_WEBHOOK_OPS"
# Expect HTTP 204
```

---

## Active Alarms by Node

### Wings nodes (`wing-euc-01`, `wing-use-01`)

Source file: `config/health.d/wings.conf` — mounted at `/etc/netdata/health.d/wings.conf` on each node.

| Alarm | Metric | Warn | Crit | Notes |
|---|---|---|---|---|
| `ram_in_use` | 5-min avg RAM | > 80% | > 90% | Overrides default (instantaneous). Stays fired 30 min after clearing. |
| `oom_kill` | OOM kills in 10 min | — | > 0 | Game servers are crashing. Immediate capacity action required. |
| `swap_in_use` | Swap used | > 0% | > 5% | Game servers must never swap. Swap = severe player lag. |
| `10min_cpu_usage` | 10-min avg CPU | > 85% | > 92% | Raised from default 75%/85% — game servers run hot. |
| `10min_cpu_iowait` | 10-min avg iowait | > 40% | > 60% | Raised from default 20% — game servers are disk-intensive. |
| `disk_space_usage` | Disk used % | > 85% | > 95% | Game server files fill disks quickly. |
| `ping_host_reachable` | Cross-node ping | — | Unreachable | euc pings use-01; use pings euc-01. Fires if datacenter link breaks. |
| `ping_packet_loss` | Packet loss % | > 5% | > 10% | Network degradation between Wing nodes. |

Default Netdata alarms also active (not overridden):
- `disk_inode_usage` — inode exhaustion
- `1hour_memory_hw_corrupted` — ECC hardware errors
- `docker_container_unhealthy` — Docker container health check failures

### Parent (Azure ACI)

| Alarm | Metric | Trigger | Notes |
|---|---|---|---|
| `httpcheck_web_service_unreachable` | `panel.pexnode.com` HTTP | Non-200/302/401 response | Panel down |
| `httpcheck_web_service_unreachable` | `billing.pexnode.com` HTTP | Non-200/302 response | Billing down |
| `httpcheck_web_service_no_connection` | Either endpoint | Connection refused/timeout | Server unreachable |

---

## Response Playbooks

### RAM warning on a Wings node (> 80%)

1. Check which game servers are running: `curl -s "$PEXNODE_PANEL_URL/api/application/servers" -H "Authorization: Bearer $PEXNODE_PTERO_APPLICATION_API_KEY" | jq '.data[].attributes | {name,node,limits.memory}'`
2. Check current RAM on the node: `ssh ubuntu@$WING_EUC01_HOST "free -h"`
3. If consistently high: provision a new Wings node (see `docs/30-Runbooks/Wings-Node-Provisioning.md`)
4. If a single server is OOM-looping: investigate that server's config in the panel

**Threshold rationale**: A 5-minute average > 80% means the node is running hot during real gameplay, not just a startup spike. Sustained = need a new node.

### OOM kill on a Wings node (CRITICAL)

1. **Immediately** check which process was killed:
   ```bash
   ssh ubuntu@$WING_EUC01_HOST "sudo dmesg | grep -i 'oom\|killed' | tail -20"
   ```
2. If a game server container was killed: Pterodactyl will attempt to restart it
3. Notify affected customers if server is down
4. Provision a new Wings node immediately — this node is over-committed

### Swap usage on a Wings node

This should never happen. If it fires:
1. SSH to the node and check: `free -h`
2. Identify the process using swap: `sudo smem -s swap -r | head -20`
3. The node is critically over-committed — treat same as OOM kill response

### `panel.pexnode.com` unreachable

1. Verify via external check: `curl -I https://panel.pexnode.com`
2. If unreachable from outside: SSH to `ptero-prod` and check services
   ```bash
   source scripts/load-env.sh
   scripts/connect.sh ptero-prod
   systemctl status nginx php8.1-fpm
   ```
3. If panel server is down: escalate, check provider status

### `billing.pexnode.com` unreachable

1. Verify: `curl -I https://billing.pexnode.com`
2. WHMCS is on shared hosting (InterServer) — SSH to check:
   ```bash
   scripts/connect.sh whmcs-prod
   ```
3. If provider-side outage: check InterServer status page

### Cross-node ping failure (`ping_host_reachable: CRITICAL`)

1. First verify the node itself is up (check other alarms from it — if RAM/CPU alarms still firing, node is up)
2. If node is up but ping fails: routing/firewall issue between datacenters
3. If node is down: game servers on that node are unreachable — notify customers

---

## Silence / Acknowledge Alerts

Via Netdata Cloud UI (`app.netdata.cloud`):
1. Open the alert → **Silence** (choose duration) to suppress repeat notifications
2. **Acknowledge** to mark as seen without suppressing

Via API (silence specific alarm for 1 hour):
```bash
curl -s -X POST "http://pexnode-netdata.norwayeast.azurecontainer.io:19999/api/v1/manage/health" \
  -d "cmd=SILENCE_ALL&duration=3600"
```

---

## Updating Alert Thresholds

Edit `config/health.d/wings.conf`, then deploy without container restart:
```bash
source /home/hakon/git/pexnode_ops_agent/.env
SSH_OPTS="-o StrictHostKeyChecking=no -i $DEPLOY_SSH_KEY"

for node in "$WING_EUC01_SSH_USER@$WING_EUC01_HOST" "$WING_USE01_SSH_USER@$WING_USE01_HOST"; do
  scp $SSH_OPTS config/health.d/wings.conf "${node}:/tmp/wings.conf"
  ssh $SSH_OPTS "$node" "sudo cp /tmp/wings.conf /opt/netdata/health.d/wings.conf"
done

git add config/health.d/wings.conf && git commit -m "chore: update Wings alarm thresholds"
```

Netdata hot-reloads health configs via SIGHUP automatically.
