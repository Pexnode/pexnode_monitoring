# Complete Platform Setup Guide

End-to-end setup for Pexnode monitoring infrastructure.

---

## Phase 1: Deploy Monitoring Parent (5 min)

### 1.1 Get Netdata Token

Visit https://app.netdata.cloud:
1. Sign up (free tier)
2. Create a space (or use default)
3. Settings → Nodes & Agents
4. Copy "Claim Token"

### 1.2 Deploy on Azure

```bash
cd azure
cp .env.template .env.local

# Edit .env.local, add token:
# NETDATA_CLAIM_TOKEN=abc123...
# NETDATA_CLAIM_URL=https://app.netdata.cloud

docker-compose up -d
```

Or deploy low-cost Azure ACI from scripts (recommended for automation):

```bash
export AZURE_SUBSCRIPTION_ID=<sub_id>
export AZURE_SP_APP_ID=<app_id>
export AZURE_SP_PASSWORD=<secret>
export AZURE_SP_TENANT_ID=<tenant>
export NETDATA_CLAIM_TOKEN=<netdata_claim_token>

./scripts/azure/deploy-netdata-aci.sh
```

One-time service principal bootstrap helper:

```bash
./scripts/azure/bootstrap-service-principal.sh <sub_id> pexnode-monitoring pexnode-monitoring-ops
```

Get public IP:
```bash
docker ps
# Note the public IP assigned by Azure
```

### 1.3 Verify Parent Running

Access dashboard:
```
https://<azure-ip>:19999
```

Should show:
- No child nodes yet (will add in Phase 2-3)
- Parent metrics (system.cpu, system.memory, etc.)

---

## Phase 2: Enroll Existing Hosts (5 min)

### 2.1 Enroll Pterodactyl Host

```bash
./scripts/enroll-host.sh 74.50.65.10 <your-claim-token>
```

Script will:
- SSH to host, test connectivity
- Install Docker (if needed)
- Deploy Netdata child container
- Setup auto-start on reboot

### 2.2 Enroll WHMCS Host

```bash
./scripts/enroll-host.sh 104.37.190.203 <your-claim-token>
```

### 2.3 Verify in Dashboard

Wait 60 seconds, then check:
```
https://app.netdata.cloud → Your Space
```

Should show 3 nodes:
- `netdata-parent` (Azure)
- `pterodactyl-host` (74.50.65.10)
- `whmcs-host` (104.37.190.203)

If you see them but no metrics, wait 2-3 more minutes for data collection.

---

## Phase 3: Configure Alerts (5-10 min)

### 3.1 Email Setup (SMTP)

Edit `azure/netdata.conf` with your SMTP provider:

```ini
[mail]
  enabled = yes
  host = smtp.gmail.com
  port = 587
  username = your-email@gmail.com
  password = ${NETDATA_ALERT_SMTP_PASSWORD}
  from = alerts@pexnode.com
  tls = yes
```

Add to `azure/.env.local`:
```bash
NETDATA_ALERT_SMTP_PASSWORD=your_app_password
```

Rebuild parent:
```bash
cd azure
docker-compose down
docker-compose up -d
```

### 3.2 Mobile App Setup

1. Install Netdata app (iOS/Android)
2. Add server: `https://<azure-ip>:19999`
3. Sign in with Netdata Cloud account
4. Enable notifications in app settings

### 3.3 Configure Alert Rules

Place custom rules in `azure/health.d/` directory. Example:

**File: `azure/health.d/cpu-load.conf`**

```
alarm: cpu_load_high
  on: system.load
  lookup: average -1m of load15
  warn: $this > 0.80
  crit: $this > 0.95
  repeat: 30m
```

**File: `azure/health.d/memory.conf`**

```
alarm: memory_usage_high
  on: system.ram
  lookup: average -1m of used
  calc: ($this / ($this + $free)) * 100
  warn: $this > 85
  crit: $this > 95
  repeat: 30m
```

Rebuild:
```bash
cd azure
docker-compose restart netdata
```

See [docs/ALERT-RUNBOOK.md](docs/ALERT-RUNBOOK.md) for more alert examples.

---

## Phase 4: Provision New Wings Node (10-15 min)

### 4.1 Create Node in Panel

In Pterodactyl Admin:
1. Admin Panel → Nodes
2. Create New
3. Set name, description, location
4. Configure memory/CPU limits
5. Save and note the Node ID

Get your Application API key:
1. Admin Panel → API → Application Keys
2. Create New
3. Set permissions: `nodes.*`
4. Copy key (starts with `ptla_`)

### 4.2 Provision Node

On your local machine:

```bash
./scripts/provision-wings-node.sh \
  https://panel.pexnode.com \
  <node-id> \
  <api-key> \
  <netdata-token> \
  <ssh-port>

# Example:
./scripts/provision-wings-node.sh \
  https://panel.pexnode.com \
  2 \
  ptla_abc123xyz789 \
  def456ghi789 \
  2222
```

This will:
- Install Wings daemon
- Configure panel integration
- Enroll in monitoring
- Harden security:
  - Change SSH port
  - Enable firewall (UFW)
  - Setup Fail2Ban
  - Apply kernel hardening
  - Enable automatic updates

Script runs ~5-10 minutes. Check progress:

```bash
# SSH to host while provisioning
ssh -p 2222 root@<host-ip>
tail -f /var/log/pexnode-provision.log
```

### 4.3 Verify Node in Panel

After provisioning completes:

1. Check Wings running:
   ```bash
   ssh -p 2222 root@<host-ip>
   systemctl status wings
   ```

2. In panel:
   ```
   Admin Panel → Nodes → Your Node
   → Should show "Online" (green)
   ```

3. Verify in monitoring:
   ```
   https://app.netdata.cloud → Nodes
   → New node appears as "<hostname>-wings"
   ```

### 4.4 Allocate Ports

In panel:
1. Admin → Nodes → Your Node → Allocations
2. Add port range: `25500-25600` (TCP + UDP)
3. Click "Submit"

Now you can provision game servers on this node.

---

## Phase 5: Auto-Provision Multiple Nodes (Terraform/Azure)

### 5.1 Using Cloud-Init

For automated provisioning in Azure, AWS, etc., pass user-data:

```bash
# Set environment
export PANEL_URL=https://panel.pexnode.com
export NODE_ID=3
export WINGS_API_KEY=ptla_xxxxx
export NETDATA_TOKEN=abc123
export SSH_PORT=2223

# Use cloud-init
az vm create \
  --resource-group pexnode-game-nodes \
  --name game-node-3 \
  --image UbuntuLTS \
  --custom-data provision-wings-bootstrap.sh \
  --environment-variables \
    PANEL_URL NODE_ID WINGS_API_KEY NETDATA_TOKEN SSH_PORT
```

See [scripts/CLOUD-INIT-SETUP.md](scripts/CLOUD-INIT-SETUP.md) for full examples (Terraform, AWS, DigitalOcean).

### 5.2 Scaling Script

For provisioning 5+ nodes:

```bash
#!/bin/bash
for i in {1..5}; do
  NODE_ID=$((i + 1))
  SSH_PORT=$((2222 + i))
  
  echo "Provisioning game-node-$i..."
  
  ./scripts/provision-wings-node.sh \
    https://panel.pexnode.com \
    "$NODE_ID" \
    "ptla_xxxxx" \
    "abc123" \
    "$SSH_PORT" &
done
wait
```

---

## Phase 6: Monitoring & Alerts

### 6.1 Dashboard Access

**Web:**
```
https://app.netdata.cloud
```

**Mobile App:**
- iOS/Android
- Real-time metrics
- Push notifications with sound

### 6.2 Typical Alert Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| CPU Load (1m avg) | 0.80 | 0.95 |
| Memory Used | 85% | 95% |
| Disk Used | 80% | 90% |
| Container Restart Loop | 3x/5m | 5x/5m |

### 6.3 Alert Response Workflow

```
Alert triggered (CPU > 80%)
    ↓
Email + SMS + Mobile app push
    ↓
Acknowledge in app or dashboard
    ↓
Investigate (view metrics, container logs)
    ↓
Manual action if needed (restart, scale up)
```

---

## Phase 7: MCP Operations Integration

Use these templates to wire monitoring + actions in your MCP server:

1. Copy environment template:

```bash
cp mcp/templates/pexnode-monitoring-mcp.env.example /path/to/pexnode_mcp/.env
```

2. Ensure required tool catalog is implemented:

```bash
cat mcp/templates/mcp-tools-required.json
```

3. Enable write actions only when ready:
- `MCP_ENABLE_WRITES=true`
- `MCP_ALLOWED_GAMES=minecraft`

4. Validate tool set against setup guide:
- `mcp/MCP-OPERATIONS-SETUP.md`

---

## Troubleshooting

### Parent Not Responding

```bash
# Check container
docker ps | grep netdata-parent

# View logs
docker logs netdata-parent | tail -50

# Restart
docker restart netdata-parent
```

### Node Not Connecting

SSH to host:
```bash
docker ps | grep netdata-child
docker logs netdata-child

# Restart
docker restart netdata-child
```

### Wings Won't Start

```bash
systemctl status wings
journalctl -u wings -n 50

# Check config
cat /etc/pterodactyl/config.yml | head -10
```

### Firewall Blocking

```bash
ufw status numbered

# Allow if needed
ufw allow 25500:25600/tcp
```

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more.

---

## Security Checklist

✅ After Phase 2:
- [ ] Parent running on Azure with valid SSL
- [ ] Both existing hosts enrolled in monitoring
- [ ] SMTP configured for alerts

✅ After Phase 3:
- [ ] Email alerts working
- [ ] Mobile app receiving notifications
- [ ] Custom alert rules deployed

✅ After Phase 4+:
- [ ] New Wings nodes provisioned
- [ ] SSH port changed (non-22)
- [ ] UFW firewall enabled
- [ ] Fail2Ban active
- [ ] Automatic updates enabled

---

## Next Steps

1. **Add more Wings nodes** — repeat Phase 4
2. **Create game servers** — use panel UI or API
3. **Setup load balancing** — distribute customers across nodes
4. **Backup strategies** — implement snapshot schedule
5. **Performance tuning** — monitor and adjust resource limits

---

## Support

- Monitoring: [docs/ALERT-RUNBOOK.md](docs/ALERT-RUNBOOK.md)
- Wings: [docs/WINGS-PROVISIONING.md](docs/WINGS-PROVISIONING.md)
- Troubleshooting: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- MCP Integration: [mcp/monitoring-tools.md](mcp/monitoring-tools.md)
