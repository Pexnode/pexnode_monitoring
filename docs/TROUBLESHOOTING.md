# Troubleshooting Guide

## Common Issues

### Parent Container Won't Start

**Problem:** `docker-compose up -d` fails or container exits immediately

**Check:**
```bash
docker logs netdata-parent
```

**Solutions:**

1. **Port 19999 already in use:**
   ```bash
   lsof -i :19999
   # Kill other process or change port in docker-compose.yml
   ```

2. **Claim token invalid:**
   - Get new token from https://app.netdata.cloud/spaces/overview
   - Update `.env.local` and restart

3. **Out of memory:**
   - Check Azure Container Instances allocated memory
   - Minimum: 512MB (1GB recommended)

4. **Network connectivity:**
   - Verify outbound HTTPS to `app.netdata.cloud`
   - Check firewall rules in Azure

---

### Child Not Connecting to Parent

**Problem:** Child container running but not appearing in dashboard

**Check:**
```bash
# SSH to host
docker logs netdata-child | head -50
```

**Solutions:**

1. **Wrong claim token:**
   ```bash
   # Re-enroll
   ./scripts/unenroll-host.sh <host-ip>
   ./scripts/enroll-host.sh <host-ip> <correct-token>
   ```

2. **Docker network issues:**
   ```bash
   docker exec netdata-child curl -v https://app.netdata.cloud
   docker exec netdata-child nslookup app.netdata.cloud
   ```

3. **Container misconfigured:**
   ```bash
   docker inspect netdata-child | grep -A5 Environment
   # Verify NETDATA_CLAIM_TOKEN is set
   ```

4. **Hostname conflicts:**
   - Each child needs unique hostname
   - Check: `docker exec netdata-child hostname`

---

### No Metrics Showing in Dashboard

**Problem:** Nodes appear but no data/graphs

**Solutions:**

1. **Wait 2-3 minutes** for first metric collection

2. **Check data collection:**
   ```bash
   docker exec netdata-child curl http://localhost:19999/api/v1/data?chart=system.cpu
   ```

3. **Verify parent is collecting:**
   ```bash
   docker logs netdata-parent | grep -i "streaming\|collecting"
   ```

4. **Restart children:**
   ```bash
   ssh root@<host-ip> docker restart netdata-child
   ```

---

### Email Alerts Not Sending

**Problem:** Alert fires but no email received

**Check:**
```bash
docker logs netdata-parent | grep -i "mail\|smtp\|notification"
```

**Solutions:**

1. **SMTP credentials wrong:**
   - Verify `.env.local` has correct password
   - For Gmail, use app-specific password (not main password)
   - Test manually:
     ```bash
     docker exec netdata-parent \
       telnet smtp.gmail.com 587
     ```

2. **Email not configured:**
   - Check `azure/netdata.conf` has `[mail]` section
   - Rebuild: `docker-compose down && docker-compose up -d`

3. **Recipient not set:**
   - Set default email in dashboard: Settings → Notifications → Email

4. **Alert rule not triggering:**
   - Check threshold is reasonable (not 0 or 999)
   - Verify metric data is flowing

---

### Mobile App Can't Connect

**Problem:** "Server unreachable" in Netdata mobile app

**Solutions:**

1. **Firewall blocking:**
   - Ensure Azure Network Security Group allows 0.0.0.0/0:19999
   - Check corporate firewall on your network

2. **DNS resolution:**
   - Use IP address directly if domain doesn't work
   - E.g., `https://52.123.45.67:19999` (not ideal for HTTPS but works for testing)

3. **SSL certificate:**
   - If using custom domain, ensure valid certificate
   - Self-signed certificates won't work in mobile app

4. **Parent not responding:**
   ```bash
   curl -k https://<parent-ip>:19999/api/v1/info
   ```

5. **Try on different network:**
   - Test on 4G/LTE to rule out corporate WiFi firewall

---

### Host Disappears from Dashboard (Intermittent)

**Problem:** Node appears and disappears randomly

**Causes & Solutions:**

1. **Child container crashing:**
   ```bash
   docker ps | grep netdata-child  # should be "Up"
   docker logs netdata-child
   ```

2. **Network connectivity drops:**
   - Check host network stability: `ping 8.8.8.8`
   - Review host internet speed

3. **Parent memory full:**
   - Increase parent container memory in Azure

4. **DNS issues:**
   - Restart child container: `docker restart netdata-child`

---

### Alerts Firing Constantly

**Problem:** Alert keeps triggering repeatedly

**Solutions:**

1. **Threshold too low:**
   ```bash
   # Check threshold vs actual value
   docker logs netdata-parent | grep -A2 "alarm_id"
   ```

2. **Increase repeat interval:**
   - Edit alert rule in `azure/health.d/`
   - Change `repeat: 10m` to `repeat: 30m` or longer
   - Rebuild container

3. **Acknowledge and silence:**
   - Dashboard → Alert → Silence for X minutes
   - Manual silence gives operators time to investigate

---

### Docker/Container Issues

**Container won't start after reboot:**
```bash
ssh root@<host-ip>

# Check auto-start service
systemctl status pexnode-netdata-child.service

# Manually start
/opt/pexnode-monitoring/enroll-child.sh

# Check logs
journalctl -u pexnode-netdata-child.service -f
```

**Out of disk space on monitored host:**
```bash
# Check disk usage
df -h

# Clear old Docker logs
find /var/lib/docker/containers -name "*.log" -exec truncate -s 0 {} \;

# Prune old containers/images
docker system prune -a
```

---

## Health Check Commands

Run these to verify monitoring health:

```bash
# 1. Parent container
docker ps | grep netdata-parent  # should be "Up"
docker logs netdata-parent | tail -20

# 2. Both hosts (SSH)
for host in 74.50.65.10 104.37.190.203; do
  echo "=== $host ==="
  ssh root@$host "docker ps | grep netdata-child"
done

# 3. API connectivity
curl -s http://localhost:19999/api/v1/info | jq '.version'

# 4. Netdata Cloud
# Visit https://app.netdata.cloud and verify nodes appear
```

---

## Reset / Troubleshooting Scripts

**Full restart of monitoring:**
```bash
# On each host
./scripts/unenroll-host.sh 74.50.65.10
./scripts/unenroll-host.sh 104.37.190.203

# Stop parent
cd azure && docker-compose down

# Get fresh token
# ... go to app.netdata.cloud ...

# Restart everything
cd azure && docker-compose up -d
./scripts/enroll-host.sh 74.50.65.10 <new-token>
./scripts/enroll-host.sh 104.37.190.203 <new-token>
```

**Check all metrics are flowing:**
```bash
# Show all metrics being collected on a host
ssh root@<host-ip> "docker exec netdata-child curl -s http://localhost:19999/api/v1/data?format=json | jq '.data | keys'"
```

---

## Getting Help

1. **Netdata documentation**: https://learn.netdata.cloud/
2. **Ops repo runbooks**: `/home/hakon/git/pexnode_ops_agent/docs/30-Runbooks/`
3. **Check if this is mentioned**: `grep -r "error_you_see" pexnode_monitoring/docs/`
