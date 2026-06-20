# Deployment Guide

Covers deploying the Netdata parent on Azure and enrolling child nodes.
For alert details see [ALERT-RUNBOOK.md](ALERT-RUNBOOK.md).

---

## Architecture

```
[wing-euc-01]  ──stream──►
[wing-use-01]  ──stream──►  [netdata-parent on Azure ACI]  ──►  Discord #ops
[future nodes] ──stream──►                                  ──►  Netdata Cloud
```

- **Parent**: Azure Container Instance, resource group `Pexnode`, container `netdata-parent`
- **FQDN**: `pexnode-netdata.norwayeast.azurecontainer.io` (stable; IP changes on each redeploy)
- **Children**: Netdata agents running in Docker on each Wings host
- **Streaming key**: UUID `449c2b8f-8a52-467c-b6e6-2532dfafadc2` stored as `NETDATA_STREAMING_API_KEY`

---

## Prerequisites

- Azure service principal with `Contributor` on the `Pexnode` resource group
- Netdata Cloud account and claim token (`NETDATA_CLAIM_TOKEN`)
- SSH key access to Wing nodes (`DEPLOY_SSH_KEY`)
- Discord webhook URL for the `#ops` channel (`DISCORD_WEBHOOK_OPS`)
- All secrets stored in `pexnode_ops_agent/.env` (loaded via `source scripts/load-env.sh`)

---

## Deploy / Redeploy Parent (Azure ACI)

The deploy script deletes and recreates the ACI container. This changes the public IP but the FQDN stays the same — children always use the FQDN.

```bash
cd /home/hakon/git/pexnode_monitoring

# Load secrets (Azure SP + Netdata + Discord)
source /home/hakon/git/pexnode_ops_agent/.env

# Authenticate Azure CLI (if not already logged in)
az login --service-principal \
  -u "$AZURE_SP_APP_ID" -p "$AZURE_SP_PASSWORD" \
  --tenant "$AZURE_SP_TENANT_ID" -o none

# Deploy / redeploy
bash scripts/azure/deploy-netdata-aci.sh
```

Required env vars:

| Variable | Purpose |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | Azure subscription |
| `AZURE_SP_APP_ID` | Service principal app ID |
| `AZURE_SP_PASSWORD` | Service principal secret |
| `AZURE_SP_TENANT_ID` | Azure tenant ID |
| `NETDATA_CLAIM_TOKEN` | Netdata Cloud claim token |
| `NETDATA_STREAMING_API_KEY` | UUID streaming key (`449c2b8f-8a52-467c-b6e6-2532dfafadc2`) |
| `DISCORD_WEBHOOK_OPS` | Discord webhook URL for `#ops` |

**What the deploy script writes at container startup** (via `--command-line`):

- `/etc/netdata/health_alarm_notify.conf` — Discord alert config pointing at `DISCORD_WEBHOOK_OPS`
- `/etc/netdata/stream.conf` — receiver config accepting UUID streaming key from children
- `/etc/netdata/go.d/httpcheck.conf` — HTTP availability checks for panel + billing

After deploy, dashboard is at:
```
http://pexnode-netdata.norwayeast.azurecontainer.io:19999
```

---

## Enroll a New Host

```bash
cd /home/hakon/git/pexnode_monitoring
source /home/hakon/git/pexnode_ops_agent/.env

./scripts/enroll-host.sh <host_ip> "$NETDATA_CLAIM_TOKEN"
```

The script will:
1. Test SSH access (expects `root` user + `DEPLOY_SSH_KEY`)
2. Verify Docker is installed
3. Write `/opt/netdata/stream.conf` (FQDN + UUID key)
4. Write `/opt/netdata/health.d/` (alarm config dir)
5. Write `/opt/netdata/go.d/` (collector config dir)
6. Deploy `netdata-child` container with `--restart=unless-stopped`
7. Register a systemd service for reboot persistence

Volume mounts on child container:

| Host path | Container path | Purpose |
|---|---|---|
| `/opt/netdata/stream.conf` | `/etc/netdata/stream.conf` | Streaming config (parent FQDN + key) |
| `/opt/netdata/health.d/` | `/etc/netdata/health.d/` | Custom health alarm overrides |
| `/opt/netdata/go.d/` | `/etc/netdata/go.d/` | Custom collector configs (ping, etc.) |
| `/proc` | `/host/proc` | Host metrics |
| `/sys` | `/host/sys` | Host metrics |
| `/var/run/docker.sock` | `/var/run/docker.sock` | Docker container monitoring |

---

## Enrolled Nodes (current)

| Node | IP | Region | Notes |
|---|---|---|---|
| `wing-euc-01` | `147.135.138.58` | EU Central | Wings game server host |
| `wing-use-01` | `167.114.211.79` | US East | Wings game server host |

**Not yet enrolled:** `ptero-prod` (panel server), `whmcs-prod` (billing server). Enrolling them would add internal CPU/RAM/disk metrics. HTTP availability is monitored externally via httpcheck on the parent.

---

## Wings-Specific Config

Each Wings node has these files in `/opt/netdata/`:

### `health.d/wings.conf`
Custom alarm thresholds tuned for game server hosts. Source file: `config/health.d/wings.conf`.

Update and redeploy:
```bash
# Push updated config and hot-reload (no container restart needed)
source /home/hakon/git/pexnode_ops_agent/.env
SSH_OPTS="-o StrictHostKeyChecking=no -i $DEPLOY_SSH_KEY"

for node in "$WING_EUC01_SSH_USER@$WING_EUC01_HOST" "$WING_USE01_SSH_USER@$WING_USE01_HOST"; do
  scp $SSH_OPTS config/health.d/wings.conf "${node}:/tmp/wings.conf"
  ssh $SSH_OPTS "$node" "sudo cp /tmp/wings.conf /opt/netdata/health.d/wings.conf"
done
```

### `go.d/ping.conf`
Each Wings node pings the other for cross-datacenter reachability. Content is node-specific (written at deploy time):
- wing-euc-01 pings `167.114.211.79` (wing-use-01)
- wing-use-01 pings `147.135.138.58` (wing-euc-01)

---

## Streaming Protocol

Children stream metrics to the parent using the Netdata streaming protocol. Key facts:

- Children connect **outbound** to the parent on port `19999` — no inbound firewall rules needed on the child
- Streaming key **must be a valid UUID** (Netdata v2 requirement)
- Active key: `449c2b8f-8a52-467c-b6e6-2532dfafadc2`
- Children retry with exponential backoff if the parent is temporarily unreachable
- Parent `stream.conf` is written at ACI startup; changing it requires a parent redeploy

---

## Troubleshooting

### Child not connecting to parent

```bash
# Check container is running
ssh ubuntu@$WING_EUC01_HOST "sudo docker ps --filter name=netdata-child"

# Check stream logs
ssh ubuntu@$WING_EUC01_HOST "sudo docker logs --tail 30 netdata-child 2>&1 | grep STREAM"

# Verify stream.conf has correct key and FQDN
ssh ubuntu@$WING_EUC01_HOST "cat /opt/netdata/stream.conf"
```

Common causes:
- Wrong streaming key (must be exact UUID)
- FQDN not resolving (DNS propagation after parent redeploy)
- Child can't reach parent on port 19999 (firewall)

### Parent not receiving streams

```bash
# Check parent received the stream.conf at startup
az container exec -g Pexnode -n netdata-parent \
  --exec-command "cat /etc/netdata/stream.conf"

# Check mirrored hosts via API
curl -s http://pexnode-netdata.norwayeast.azurecontainer.io:19999/api/v1/info \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['mirrored_hosts'])"
```

### Discord alerts not firing

```bash
# Verify health_alarm_notify.conf was written
az container exec -g Pexnode -n netdata-parent \
  --exec-command "cat /etc/netdata/health_alarm_notify.conf"

# Test webhook manually
curl -X POST -H "Content-Type: application/json" \
  -d '{"content":"test"}' "$DISCORD_WEBHOOK_OPS"
```

2. Sign up or log in
3. Go to **Spaces** → **Settings** → **Nodes & Agents**
4. Copy the **Claim Token**
5. Also note the **Claim URL** (typically `https://app.netdata.cloud`)

---

## Step 2: Deploy Parent Container on Azure

### Option A: Azure Container Instances (Easiest)

1. Clone/download this repo to your dev machine
2. Create `.env.local`:

```bash
cd azure
cp .env.template .env.local
# Edit .env.local and paste your NETDATA_CLAIM_TOKEN
```

3. Deploy to Azure:

```bash
# Using Azure CLI
az container create \
  --resource-group pexnode-monitoring \
  --name netdata-parent \
  --image netdata/netdata:latest \
  --cpu 1 \
  --memory 1 \
  --ports 19999 \
  --environment-variables \
    NETDATA_CLAIM_TOKEN="your-token" \
    NETDATA_CLAIM_URL="https://app.netdata.cloud" \
    NETDATA_TELEMETRY="no"
```

4. Get public IP:

```bash
az container show \
  --resource-group pexnode-monitoring \
  --name netdata-parent \
  --query ipAddress.ip \
  --output tsv
```

Note this IP. Your dashboard will be at: `https://<ip>:19999`

### Option B: Docker Compose (Testing)

```bash
cd azure
docker-compose up -d
# Access at http://localhost:19999
```

---

## Step 3: Configure Azure Networking

If using Azure Container Instances, ensure:

1. **Inbound rules** allow `0.0.0.0:19999`
2. **Outbound rules** allow:
   - HTTPS to `app.netdata.cloud` (claiming/syncing)
   - HTTPS to container registries (pulling images)

---

## Step 4: Enroll Existing Hosts

### Enroll Pterodactyl Host

```bash
./scripts/enroll-host.sh 74.50.65.10 <your-claim-token>
```

This will:
- Test SSH access
- Verify Docker is installed
- Deploy Netdata child container
- Setup auto-enrollment on reboot

### Enroll WHMCS Host

```bash
./scripts/enroll-host.sh 104.37.190.203 <your-claim-token>
```

### Verify Enrollment

After ~30 seconds, check in Netdata Cloud:
1. Go to https://app.netdata.cloud
2. You should see nodes appearing:
   - `netdata-parent`
   - `pterodactyl-host` (or hostname)
   - `whmcs-host` (or hostname)

---

## Step 5: Configure Alerts

See [ALERT-RUNBOOK.md](ALERT-RUNBOOK.md) for:
- Email/SMTP setup
- Mobile app installation
- Custom alert rules
- Notification channels

---

## Step 6: Auto-Enrollment for New Servers

When you provision a new game node server, include this in the boot script:

```bash
#!/bin/bash
export NETDATA_CLAIM_TOKEN="your-token"
export NETDATA_CLAIM_URL="https://app.netdata.cloud"
curl -s https://raw.githubusercontent.com/your-org/pexnode_monitoring/main/scripts/auto-enroll-onboot.sh | bash
```

Or, bake it into your server image:

```dockerfile
FROM ubuntu:22.04
RUN curl -fsSL https://get.docker.com | sh
COPY scripts/auto-enroll-onboot.sh /opt/pexnode-monitoring/
RUN chmod +x /opt/pexnode-monitoring/auto-enroll-onboot.sh && \
    /opt/pexnode-monitoring/auto-enroll-onboot.sh
```

---

## Step 7: Dashboard & Monitoring

Once nodes are enrolled, you can:

1. **Access dashboard**: `https://app.netdata.cloud` (web) or mobile app
2. **View metrics**:
   - CPU, Memory, Disk per host
   - Per-container resource usage (Wings)
   - Network I/O
   - Process list

3. **Create dashboards**: Custom dashboards combining metrics from multiple hosts

4. **Set alerts**: Based on thresholds (see ALERT-RUNBOOK.md)

---

## Troubleshooting

### Parent Container Won't Start

```bash
# Check logs
docker logs netdata-parent

# Common issues:
# - Port 19999 already in use
# - Insufficient memory
# - Claim token invalid
```

### Child Not Connecting

SSH to host and check:

```bash
# Is container running?
docker ps | grep netdata-child

# Check logs
docker logs netdata-child

# Verify network connectivity
docker exec netdata-child curl -I https://app.netdata.cloud
```

### No Metrics Showing

1. Wait 2-3 minutes for data collection
2. Refresh dashboard (F5)
3. Check parent sees children:
   ```bash
   docker exec netdata-parent cat /var/log/netdata/debug.log | tail -20
   ```

### Claim Token Expired

Get a new token from https://app.netdata.cloud and re-enroll:

```bash
./scripts/unenroll-host.sh 74.50.65.10
./scripts/enroll-host.sh 74.50.65.10 <new-token>
```

---

## Scaling to More Hosts

To add a new host:

```bash
./scripts/enroll-host.sh <new-host-ip> <claim-token>
```

Parent automatically accepts new children. No restart required.

---

## Backup & Recovery

### Backup Configuration

Parent stores config in Docker volume. To backup:

```bash
docker run --rm \
  -v netdata_config:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/netdata-config-backup.tar.gz -C /data .
```

### Recovery

```bash
docker run --rm \
  -v netdata_config:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/netdata-config-backup.tar.gz -C /data
```

---

## Updating

Parent:
```bash
cd azure
docker-compose pull
docker-compose up -d
```

Children:
```bash
# On each host
docker pull netdata/netdata:latest
docker-compose -f <(docker run --rm netdata/netdata:latest cat /etc/docker-compose.yml) up -d
# OR manually:
docker stop netdata-child
docker rm netdata-child
# Then run: ./scripts/enroll-host.sh again
```
