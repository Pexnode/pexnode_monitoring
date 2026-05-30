# Alert Runbook

## Overview

Netdata alerts notify you when metrics exceed thresholds. Alerts are triggered on the parent node based on data from all children.

## Alert Channels

| Channel | Setup | Best For |
|---------|-------|----------|
| **Email (SMTP)** | Configure in Netdata settings | Daily summaries, critical alerts |
| **Mobile App** | iOS/Android app with push notifications | Real-time, sound/vibration alarms |
| **Discord** | Webhook integration | Team notifications |
| **Slack** | Webhook integration | Team notifications |
| **Webhooks** | Custom HTTP POST | Integration with other systems |

---

## Email / SMTP Setup

### 1. Add SMTP Config to Parent Container

Edit `azure/netdata.conf` and add:

```ini
[notification]
  # Enable notifications
  enabled = yes
  
[mail]
  # SMTP Server
  enabled = yes
  host = smtp.gmail.com
  port = 587
  username = your-email@gmail.com
  # WARNING: Store password in env var, not in file
  # Use: -e NETDATA_ALERT_SMTP_PASSWORD="xxxxx" in docker-compose
  password = ${NETDATA_ALERT_SMTP_PASSWORD}
  from = alerts@pexnode.com
  tls = yes
```

### 2. Update Docker Compose

Add to `azure/docker-compose.yml`:

```yaml
environment:
  NETDATA_ALERT_SMTP_PASSWORD: ${NETDATA_ALERT_SMTP_PASSWORD:-}
```

### 3. Update .env File

```bash
NETDATA_ALERT_SMTP_PASSWORD=your_app_password_here
```

### 4. Restart Parent

```bash
docker-compose restart netdata
```

### 5. Test Alert

In Netdata dashboard → Settings → Notifications → Test

---

## Mobile App Setup (Recommended)

### 1. Install Netdata App

- **iOS**: App Store → Search "Netdata"
- **Android**: Google Play → Search "Netdata"

### 2. Connect to Your Parent

In the app:
1. Tap **Add Server**
2. Enter: `https://<your-azure-ip>:19999` or `https://monitoring.pexnode.com`
3. Sign in with Netdata Cloud account

### 3. Enable Push Notifications

- App Settings → Notifications → Enable
- Alerts will push to phone with sound

---

## Alert Rules

### Default Alerts Provided

Netdata comes with built-in alerts. Check which are enabled:

```bash
# SSH into parent container
docker exec netdata-parent /bin/bash
ls /etc/netdata/health.d/
```

### Custom Alert Rules

Place custom alerts in `azure/health.d/` directory.

**Example: CPU Load Alert**

```
# File: azure/health.d/cpu-load.conf

alarm: cpu_load_high
  on: system.load
  lookup: average -1m of load15
  warn: $this > 0.80
  crit: $this > 0.95
  info: CPU load is $this
  repeat: 30m

alarm: cpu_load_critical
  on: system.cpu
  lookup: average -1m of system
  warn: $this > 80
  crit: $this > 95
  info: CPU usage is $this%
  repeat: 10m
```

**Example: Memory Alert**

```
# File: azure/health.d/memory.conf

alarm: memory_usage_high
  on: system.ram
  lookup: average -1m of used
  calc: ($this / ($this + $free)) * 100
  warn: $this > 85
  crit: $this > 95
  info: Memory usage is $this%
  repeat: 30m
```

**Example: Disk Alert**

```
# File: azure/health.d/disk-space.conf

alarm: disk_full
  on: disk.space
  lookup: average -1m of used
  calc: ($this / ($this + $avail)) * 100
  warn: $this > 80
  crit: $this > 90
  info: Disk usage is $this%
  repeat: 1h
```

**Example: Docker Container Restart**

```
# File: azure/health.d/container-restarts.conf

alarm: container_restart_loop
  on: cgroup.throttling_cpu
  lookup: average -5m of throttled_sec
  warn: $this > 10
  crit: $this > 30
  info: Container CPU throttled for $this sec (last 5m)
  repeat: 15m
```

### Load Custom Rules

1. Create alert file in `azure/health.d/`
2. Rebuild and restart container:

```bash
cd azure
docker-compose down
docker-compose up -d
```

---

## Alert Notification Configuration

### Webhook Example (Custom Integration)

To send alerts to a custom webhook (e.g., internal system):

```ini
[notification]
  enabled = yes
  
[webhook]
  enabled = yes
  url = https://your-api.example.com/alerts/netdata
  timeout = 5s
```

Webhook payload:

```json
{
  "alarm": "cpu_load_high",
  "status": "WARNING",
  "host": "pterodactyl-01",
  "value": 0.92,
  "threshold": 0.80
}
```

---

## Acknowledge & Silence Alerts

In Netdata dashboard:

1. Click alert
2. **Acknowledge** — mark as seen (stops repeat notifications)
3. **Silence** — temporarily mute (specify duration)

---

## Alert Thresholds (Recommended)

| Metric | Warning | Critical | Escalate | 
|--------|---------|----------|----------|
| CPU Load (15m avg) | 0.80 | 0.95 | Yes |
| Memory Used | 85% | 95% | Yes |
| Disk Used | 80% | 90% | Yes |
| Container Restart | 3x in 5m | 5x in 5m | Yes |
| Host Unreachable | N/A | After 5m | Yes |
| Network Errors | >1000/s | >5000/s | No |

---

## Troubleshooting

### Alerts Not Firing

1. Check alert is enabled:
   ```bash
   docker exec netdata-parent cat /etc/netdata/health.d/cpu-load.conf
   ```

2. Check parent logs:
   ```bash
   docker logs -f netdata-parent | grep -i alert
   ```

3. Verify notification config:
   - Dashboard → Settings → Notifications

### Email Not Sending

1. Verify SMTP password is set:
   ```bash
   docker exec netdata-parent env | grep SMTP
   ```

2. Check mail logs:
   ```bash
   docker exec netdata-parent cat /var/log/netdata/debug.log | grep -i mail
   ```

3. Test SMTP manually:
   ```bash
   docker exec netdata-parent \
     sendemail -f alerts@pexnode.com \
     -t your-email@example.com \
     -u "Test" \
     -m "Test email" \
     -s smtp.gmail.com:587 \
     -xu your-email@gmail.com \
     -xp yourpassword \
     -o tls=yes
   ```

### Mobile App Notifications Not Working

1. Ensure server is accessible: `https://<ip>:19999`
2. Check internet connection on phone
3. Reinstall app, re-add server
4. Check app permissions: Settings → Permissions → Notifications

---

## Escalation Workflow

For critical alerts (CPU, Memory, Disk):

```
Alert triggered (threshold exceeded)
    ↓
Send to: Email + SMS (if configured) + Mobile app (push)
    ↓
Wait 15 minutes (repeat cooldown)
    ↓
If still active: Send repeat notification
    ↓
After 1 hour: Escalate to on-call engineer (manual escalation)
```
