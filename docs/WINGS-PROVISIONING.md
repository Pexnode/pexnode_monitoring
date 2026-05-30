# Wings Node Provisioning Guide

## Overview

The `provision-wings-node.sh` script automates deployment and security hardening of new game server nodes.

**What it does:**
- Installs Wings daemon (Pterodactyl game server orchestrator)
- Registers node with your Pterodactyl panel
- Enrolls in Netdata monitoring
- Applies security hardening (firewall, SSH, kernel parameters)

**Time:** ~5-10 minutes

---

## Prerequisites

- Ubuntu 22.04 LTS or Debian 12+
- Root SSH access
- Application API key from Pterodactyl panel
- (Optional) Netdata claim token for monitoring

---

## Get Required Values

### 1. Pterodactyl Application API Key

In your Pterodactyl panel:
1. Admin Panel → Administration → API → Application Keys
2. Click **New Key**
3. Set permissions: `nodes.*` (full node management)
4. Copy the token (starts with `ptla_`)

### 2. Node ID

After creating a node in the panel:
1. Admin Panel → Nodes
2. Click on your new node
3. URL will show: `/nodes/<node_id>`
4. Or see ID in node list

### 3. Panel URL

Typically: `https://panel.pexnode.com`

### 4. Netdata Claim Token (Optional)

From https://app.netdata.cloud → Spaces → Settings → Nodes & Agents

---

## Usage

### Preferred: Deploy from this repository to a host IP

Run from repo root:

```bash
PANEL_URL=https://panel.pexnode.com \
WINGS_API_KEY=ptla_xxxxx \
NETDATA_TOKEN=netdata_claim_token \
./scripts/deploy-wing-host.sh 10.20.0.11 11 2222
```

Arguments:
- `10.20.0.11`: target host IP
- `11`: panel node id
- `2222`: hardened SSH port to set on target

This wrapper adds:
- Local lock (prevents duplicate deploy from this repo)
- Remote lock on host (prevents concurrent provision races)
- Upload + execute + maintenance setup in one run

### Basic (No Monitoring)

```bash
./provision-wings-node.sh \
  https://panel.pexnode.com \
  1 \
  ptla_xxxxxxxxxxxxx
```

### With Monitoring

```bash
./provision-wings-node.sh \
  https://panel.pexnode.com \
  1 \
  ptla_xxxxxxxxxxxxx \
  abc123defg456hij789
```

### With Custom SSH Port

```bash
./provision-wings-node.sh \
  https://panel.pexnode.com \
  1 \
  ptla_xxxxxxxxxxxxx \
  abc123defg456hij789 \
  2222
```

After direct provisioning, run maintenance installer:

```bash
./scripts/setup-host-maintenance.sh
```

---

## What Gets Hardened

### SSH

- **Custom port** (default 22, changeable)
- **Key-only auth** (no passwords)
- **Rate limiting** (3 attempts per 30s)
- **Timeout** (30s login grace period, 5m idle timeout)

### Firewall (UFW)

- Default deny inbound
- Allow SSH (on custom port)
- Allow game server ports (25500-25600/tcp+udp)
- Allow HTTP/HTTPS if needed
- Rate limit SSH

### Fail2Ban

- Ban after 3 failed SSH attempts
- Ban duration: 2 hours (SSH), 1 hour (others)
- Monitors logs automatically

### Kernel

- Disable ICMP redirects
- Enable SYN cookies (DoS protection)
- Disable source routing
- Log suspicious packets
- TCP time-wait hardening

### Updates

- Automatic security updates (unattended-upgrades)
- Reboot on major kernel updates (configurable)

---

## Post-Provisioning

### 1. Verify Node in Panel

```
Panel → Admin → Nodes → Your Node
→ Should show "Online"
```

### 2. Check Wings Status

SSH to the host:

```bash
ssh -p <port> root@<host-ip>
systemctl status wings
journalctl -u wings -f  # Follow logs
```

### 3. Allocate Ports

```
Panel → Admin → Nodes → Your Node → Allocations
→ Add port ranges for game servers
→ Typical: 25500-25600 (for 100 servers)
```

### 4. Create First Server

```
Panel → Create Server → Select this node
→ Provision (allocates resources + game container)
→ Server appears in customer dashboard
```

### 5. Monitor in Netdata (if enrolled)

```
https://app.netdata.cloud → Your Space → Nodes
→ New node appears as "<hostname>-wings"
→ View CPU, RAM, disk, container metrics
```

---

## Troubleshooting

### Wings Won't Start

SSH to host and check:

```bash
# Verify config file
cat /etc/pterodactyl/config.yml | head -20

# Check Wings logs
journalctl -u wings -n 50

# Test Wings manually
/usr/local/bin/wings -d
```

Common issues:
- API key invalid → get new key from panel
- Node ID wrong → verify in panel URL
- Panel unreachable → check firewall/DNS

### SSH Won't Connect After Hardening

```bash
# Test with new port
ssh -v -p 2222 root@<host-ip>

# If locked out, use Azure/console access to fix
ssh -p 22 root@<host-ip>  # Old port
# Or modify /etc/ssh/sshd_config manually
```

### Firewall Blocking Connections

Check UFW rules:

```bash
ssh -p <port> root@<host-ip>
ufw status numbered

# If needed, allow additional ports
ufw allow 30000:30100/tcp
```

### Node Not Showing in Panel

1. Check Wings is running: `systemctl status wings`
2. Check logs: `journalctl -u wings -n 100`
3. Verify node exists in panel (Admin → Nodes)
4. Try restarting Wings: `systemctl restart wings`

---

## Scaling to More Nodes

Repeat for each new node:

```bash
PANEL_URL=https://panel.pexnode.com \
WINGS_API_KEY=<your_api_key> \
NETDATA_TOKEN=<netdata_token> \
./scripts/deploy-wing-host.sh <new-host-ip> <next_node_id> <ssh_port>
```

Parent container (Netdata) automatically accepts new children nodes.

---

## Updating Wings

```bash
# SSH to node
ssh -p <port> root@<host-ip>

# Stop Wings
systemctl stop wings

# Update binary (in script, set WINGS_VERSION)
curl -L -o /usr/local/bin/wings \
  "https://github.com/pterodactyl/wings/releases/download/v1.11.9/wings_linux_amd64"
chmod u+x /usr/local/bin/wings

# Restart
systemctl start wings

# Verify
/usr/local/bin/wings --version
```

---

## Backup Configuration

```bash
# Before changes, backup
cp /etc/pterodactyl/config.yml /etc/pterodactyl/config.yml.backup

# Restore if needed
cp /etc/pterodactyl/config.yml.backup /etc/pterodactyl/config.yml
systemctl restart wings
```

---

## Manual Provisioning (If Script Fails)

If the script doesn't work, you can provision manually:

```bash
# 1. Install Docker
curl -fsSL https://get.docker.com | sh

# 2. Download Wings
curl -L -o /usr/local/bin/wings \
  https://github.com/pterodactyl/wings/releases/download/v1.11.8/wings_linux_amd64
chmod u+x /usr/local/bin/wings

# 3. Get config from panel API
curl -H "Authorization: Bearer ptla_xxxxx" \
  https://panel.pexnode.com/api/application/nodes/1/configuration \
  > /etc/pterodactyl/config.yml

# 4. Create systemd service (see docs)
# 5. Start: systemctl start wings
```

See Pterodactyl docs: https://pterodactyl.io/community/installation-guides/wings/docker.html
