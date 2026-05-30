# Monitoring MCP Tools

This file defines MCP (Model Context Protocol) tools for integrating monitoring into Hugo AI and CLI workflows.

## Tools

### 1. `netdata.get_metrics`

Query metrics from Netdata API.

**Parameters:**
- `host` (string, required): Hostname or node name
- `metric` (string, required): Metric name (e.g., `cpu.utilization`, `mem.used`, `disk.space`)
- `aggregate` (string, optional): `avg` | `max` | `min` | `latest` (default: `latest`)
- `time_range` (string, optional): `1m` | `5m` | `1h` | `1d` (default: `1m`)

**Returns:**
```json
{
  "host": "pterodactyl-01",
  "metric": "cpu.utilization",
  "value": 45.2,
  "unit": "%",
  "timestamp": "2026-05-30T12:34:56Z",
  "status": "OK"
}
```

**Example:**
```
Hugo: "What's the CPU usage on Pterodactyl right now?"
→ get_metrics(host="pterodactyl-01", metric="cpu.utilization")
```

---

### 2. `netdata.list_alerts`

List active alerts across all nodes.

**Parameters:**
- `status` (string, optional): `CRITICAL` | `WARNING` | `CLEAR` (default: all)
- `host` (string, optional): Filter by hostname
- `limit` (integer, optional): Max results (default: 50)

**Returns:**
```json
{
  "alerts": [
    {
      "id": "cpu_load_high",
      "host": "pterodactyl-01",
      "status": "WARNING",
      "value": 85.3,
      "threshold": 80,
      "triggered_at": "2026-05-30T12:25:00Z",
      "acknowledged": false
    }
  ],
  "total": 2,
  "critical_count": 1,
  "warning_count": 1
}
```

**Example:**
```
Hugo: "Are there any critical alerts right now?"
→ list_alerts(status="CRITICAL")
```

---

### 3. `netdata.acknowledge_alert`

Acknowledge an active alert.

**Parameters:**
- `alert_id` (string, required): Alert ID
- `host` (string, required): Hostname
- `note` (string, optional): Acknowledgment note

**Returns:**
```json
{
  "success": true,
  "alert_id": "cpu_load_high",
  "host": "pterodactyl-01",
  "acknowledged_at": "2026-05-30T12:35:00Z"
}
```

**Example:**
```
Hugo: "Acknowledge the CPU alert on Pterodactyl"
→ acknowledge_alert(alert_id="cpu_load_high", host="pterodactyl-01", note="Investigating high load")
```

---

### 4. `netdata.get_host_summary`

Get comprehensive status for a host.

**Parameters:**
- `host` (string, required): Hostname

**Returns:**
```json
{
  "host": "pterodactyl-01",
  "status": "OK",
  "last_seen": "2026-05-30T12:35:10Z",
  "uptime_days": 45,
  "metrics": {
    "cpu": { "utilization": 32.1, "load_1m": 0.45, "cores": 4 },
    "memory": { "used_pct": 62.3, "used_gb": 4.1, "total_gb": 6.5 },
    "disk": { "used_pct": 71.2, "used_gb": 142.5, "total_gb": 200 },
    "network": { "in_mbps": 2.3, "out_mbps": 1.1, "errors_in": 0, "errors_out": 0 }
  },
  "containers": [
    { "name": "minecraft-001", "cpu_pct": 15.2, "mem_pct": 28.5 },
    { "name": "minecraft-002", "cpu_pct": 12.1, "mem_pct": 25.3 }
  ],
  "active_alerts": [
    { "alert": "disk_space_warning", "value": 71.2, "threshold": 80 }
  ]
}
```

**Example:**
```
Hugo: "Give me a status update on all our servers"
→ get_host_summary(host="pterodactyl-01")
→ get_host_summary(host="whmcs-01")
```

---

### 5. `netdata.set_alert_threshold`

Update an alert threshold.

**Parameters:**
- `alert_id` (string, required): Alert rule ID
- `threshold_warn` (number, required): Warning threshold
- `threshold_crit` (number, required): Critical threshold
- `repeat_minutes` (integer, optional): Alert repeat interval

**Returns:**
```json
{
  "success": true,
  "alert_id": "cpu_load_high",
  "old_threshold": { "warn": 80, "crit": 95 },
  "new_threshold": { "warn": 75, "crit": 90 },
  "effective_at": "2026-05-30T12:36:00Z"
}
```

**Example:**
```
Hugo: "Lower the CPU warning threshold to 70%"
→ set_alert_threshold(alert_id="cpu_load_high", threshold_warn=70, threshold_crit=90)
```

---

### 6. `netdata.get_metrics_timeseries`

Get historical metrics for graphing.

**Parameters:**
- `host` (string, required): Hostname
- `metric` (string, required): Metric name
- `start_time` (string, optional): ISO 8601 timestamp
- `end_time` (string, optional): ISO 8601 timestamp
- `points` (integer, optional): Data points to return (default: 100)

**Returns:**
```json
{
  "host": "pterodactyl-01",
  "metric": "cpu.utilization",
  "unit": "%",
  "start": "2026-05-30T11:35:00Z",
  "end": "2026-05-30T12:35:00Z",
  "points": [
    { "timestamp": "2026-05-30T11:35:00Z", "value": 25.3 },
    { "timestamp": "2026-05-30T11:40:00Z", "value": 28.1 },
    ...
  ]
}
```

**Example:**
```
Hugo: "Show me CPU usage for the last hour"
→ get_metrics_timeseries(host="pterodactyl-01", metric="cpu.utilization", time_range="1h")
```

---

## Implementation Notes

These tools call the Netdata API endpoints:

- `GET /api/v1/query` — metrics
- `GET /api/v1/alarms` — alerts
- `POST /api/v1/alarms/acknowledge` — acknowledge
- `GET /api/v1/data` — timeseries

**Authentication:**
- Netdata API key from parent container: `NETDATA_API_KEY` env var
- Stored securely; passed to MCP tools at runtime

**Error Handling:**
- If parent is unreachable, return: `{"error": "Parent unreachable", "status": "ERROR"}`
- If host not found, return: `{"error": "Host not found", "status": "NOT_FOUND"}`

## Integration with Hugo AI

In pexnode_mcp, register these tools so Hugo can ask:

- "What's the memory usage on whmcs?"
- "Any critical alerts?"
- "Acknowledge the disk warning"
- "Set CPU threshold to 75%"
- "Show me the last 24 hours of CPU on Pterodactyl"
