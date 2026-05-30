# Deployment Guide

## Prerequisites

- Azure Container Instances access
- SSH access to:
  - Pterodactyl host: `74.50.65.10` (root user)
  - WHMCS host: `104.37.190.203` (root user)
- Netdata Cloud account (free: https://app.netdata.cloud)

---

## Step 1: Get Netdata Claim Token

1. Go to https://app.netdata.cloud
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
