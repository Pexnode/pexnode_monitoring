# Provisioning Checklist

## Pre-Provisioning

### Monitoring Parent Setup
- [ ] Get Netdata claim token from https://app.netdata.cloud
- [ ] Deploy parent on Azure: `cd azure && docker-compose up -d`
- [ ] Get Azure public IP
- [ ] Test: Access dashboard at `https://<ip>:19999`
- [ ] Verify cloud connection in Netdata dashboard

### Pterodactyl Panel Prep
- [ ] Create node in panel: Admin → Nodes → Create New
- [ ] Note Node ID from URL or node list
- [ ] Create Application API key: Admin → API → Create new (with `nodes.*` permission)
- [ ] Copy API key (starts with `ptla_`)

### Network & SSH Prep
- [ ] Plan SSH port (e.g., 2222 for first node, 2223 for second)
- [ ] Plan port ranges for game servers (e.g., 25500-25600)
- [ ] Have SSH key ready for accessing new servers
- [ ] Verify firewall/network allows outbound to panel and monitoring

---

## Single Node Provisioning

### Step 1: Prepare
```
- [ ] Panel URL: ___________________________
- [ ] Node ID: ___________________________
- [ ] API Key: ptla_______________________
- [ ] Netdata Token: _____________________
- [ ] SSH Port: _______________________
```

### Step 2: Run Provisioning Script
```bash
./scripts/provision-wings-node.sh \
  <panel_url> \
  <node_id> \
  <api_key> \
  <netdata_token> \
  <ssh_port>
```
- [ ] Script runs successfully
- [ ] No errors in output
- [ ] Script completes and shows summary

### Step 3: Verify Wings Running
```bash
ssh -p <ssh_port> root@<node_ip>
systemctl status wings
```
- [ ] Wings service is "active (running)"
- [ ] No errors in status output

### Step 4: Verify in Panel
```
Admin Panel → Nodes → [Your Node]
```
- [ ] Node status shows "Online" (green)
- [ ] Node details display correctly

### Step 5: Verify in Monitoring
```
https://app.netdata.cloud → Nodes
```
- [ ] New node appears (e.g., "hostname-wings")
- [ ] Metrics displaying (CPU, memory, disk)
- [ ] No alert errors

### Step 6: Add Allocations
```
Admin Panel → Nodes → [Your Node] → Allocations
```
- [ ] Add port range (e.g., 25500-25600)
- [ ] Both TCP and UDP enabled
- [ ] Allocations visible in list

### Step 7: Test Provisioning Server
```
Admin Panel → Servers → Create New
```
- [ ] Select new node
- [ ] Provision test server
- [ ] Server appears in customer dashboard
- [ ] Server is "Provisioning" → "Running"

---

## Multi-Node Provisioning (5+ Nodes)

### Preparation
- [ ] Prepare node list with IDs and SSH ports
- [ ] Generate unique API key for each node (optional; can reuse)
- [ ] Create script: `provision-multiple-nodes.sh`

### Example Script
```bash
#!/bin/bash
for i in {1..5}; do
  NODE_ID=$((i + 1))
  SSH_PORT=$((2222 + i))
  
  echo "Provisioning node $NODE_ID (port $SSH_PORT)..."
  
  ./scripts/provision-wings-node.sh \
    https://panel.pexnode.com \
    $NODE_ID \
    ptla_xxxxx \
    abc123def \
    $SSH_PORT
done
```

### Execution
- [ ] Run script
- [ ] Monitor progress in separate terminal: `watch 'ssh -p <port> root@<ip> systemctl status wings'`
- [ ] All nodes show "Running"

### Post-Provisioning Verification
- [ ] All nodes appear in panel ("Online")
- [ ] All nodes appear in Netdata dashboard
- [ ] All nodes have allocations configured
- [ ] Test provisioning server on each node

---

## Security Hardening Verification

### SSH Hardening
```bash
ssh -p <port> root@<ip>
```
- [ ] Can connect with key
- [ ] Cannot connect with password (good!)
- [ ] Verify port changed: `grep Port /etc/ssh/sshd_config`

### Firewall (UFW)
```bash
ufw status numbered
```
- [ ] Default policy: deny incoming, allow outgoing
- [ ] SSH port allowed and rate-limited
- [ ] Game port range (25500-25600) allowed
- [ ] HTTP/HTTPS allowed (if needed)

### Fail2Ban
```bash
systemctl status fail2ban
```
- [ ] Service running
- [ ] Active jails: `fail2ban-client status`

### Automatic Updates
```bash
systemctl status unattended-upgrades
```
- [ ] Service enabled
- [ ] Configuration present: `ls -la /etc/apt/apt.conf.d/50unattended-upgrades`

---

## Monitoring Alerts Setup

### Email Configuration
- [ ] Edit `azure/netdata.conf` with SMTP details
- [ ] Added password to `azure/.env.local`
- [ ] Rebuilt parent: `docker-compose down && docker-compose up -d`
- [ ] Test alert sent: Dashboard → Settings → Notifications → Test

### Mobile App Alerts
- [ ] Installed Netdata app on phone
- [ ] Added server to app: `https://<ip>:19999`
- [ ] Enabled notifications in app
- [ ] Test notification received

### Custom Alert Rules
- [ ] CPU load rule: `azure/health.d/cpu-load.conf`
- [ ] Memory rule: `azure/health.d/memory.conf`
- [ ] Disk rule: `azure/health.d/disk-space.conf`
- [ ] Container restart rule (if applicable)
- [ ] Rebuilt parent for rules to take effect

---

## Post-Provisioning Tasks

### Documentation
- [ ] Updated internal docs with node details
- [ ] Recorded SSH ports for each node
- [ ] Recorded API keys used
- [ ] Documented any custom network settings

### Monitoring Baseline
- [ ] Captured baseline metrics for each node
- [ ] Set appropriate alert thresholds
- [ ] Documented alert escalation paths

### Backup & Recovery
- [ ] Backed up Wings config: `/etc/pterodactyl/config.yml`
- [ ] Backed up Netdata parent config
- [ ] Documented recovery steps

### Performance Tuning
- [ ] Monitored node under load
- [ ] Adjusted CPU/memory limits if needed
- [ ] Optimized game server container settings

---

## Sign-Off

**Provisioned by:** ___________________________  
**Date:** ___________________________  
**Nodes provisioned:** ___________________________  
**All checks passed:** [ ] Yes [ ] No  
**Notes:** 
```




```

---

## Troubleshooting During Provisioning

| Issue | Check | Fix |
|-------|-------|-----|
| Wings won't start | `systemctl status wings` | Verify API key and node ID correct |
| SSH can't connect | Check firewall allows SSH port | `ufw allow <port>/tcp` |
| Monitoring not enrolling | Check Netdata token | Rerun: `docker restart netdata-child` |
| Firewall blocks game ports | `ufw status numbered` | `ufw allow 25500:25600/tcp` |
| Kernel params didn't apply | `sysctl -a \| grep syncookies` | `sysctl -p` to reload |

See [docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) for more help.
