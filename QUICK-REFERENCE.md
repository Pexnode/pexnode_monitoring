# Quick Reference

## What's Ready Now

✅ **Complete monitoring infrastructure** with Netdata  
✅ **Wings provisioning script** with security hardening  
✅ **Auto-enrollment** for new servers  
✅ **Alert configuration** (email, mobile, webhooks)  
✅ **Cloud-init integration** (Azure, AWS, DigitalOcean, Terraform)  
✅ **MCP tools specification** for Hugo AI integration  

---

## 5-Minute Commands

### Deploy Monitoring Parent
```bash
cd azure
cp .env.template .env.local
# Edit .env.local with your Netdata token
docker-compose up -d
```

### Enroll Existing Hosts
```bash
./scripts/enroll-host.sh 74.50.65.10 <token>
./scripts/enroll-host.sh 104.37.190.203 <token>
```

### Provision New Wings Node
```bash
./scripts/provision-wings-node.sh \
  https://panel.pexnode.com \
  <node-id> \
  ptla_xxxxx \
  <netdata-token> \
  <ssh-port>
```

### View Monitoring
```
https://app.netdata.cloud
```

---

## File Map

| What | Where |
|------|-------|
| **Start here** | [docs/COMPLETE-SETUP.md](docs/COMPLETE-SETUP.md) |
| **Quick start** | [docs/QUICK-START.md](docs/QUICK-START.md) |
| **Alerts** | [docs/ALERT-RUNBOOK.md](docs/ALERT-RUNBOOK.md) |
| **Wings provisioning** | [docs/WINGS-PROVISIONING.md](docs/WINGS-PROVISIONING.md) |
| **Cloud deployment** | [scripts/CLOUD-INIT-SETUP.md](scripts/CLOUD-INIT-SETUP.md) |
| **Troubleshooting** | [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |
| **Checklist** | [PROVISIONING-CHECKLIST.md](PROVISIONING-CHECKLIST.md) |
| **MCP tools** | [mcp/monitoring-tools.md](mcp/monitoring-tools.md) |

---

## Infrastructure Components

```
Azure Container (Parent)
├── Netdata daemon
├── Alert engine
└── Dashboard access :19999

Each Host / Node
├── Netdata child (monitoring)
└── Wings daemon (game servers)
```

---

## What Gets Monitored

**Hosts:**
- CPU load, usage, temperature
- Memory (free, used, cached)
- Disk I/O and space
- Network (bytes, packets, errors)

**Containers:**
- Per-Wings container RAM usage
- Per-container CPU usage
- Per-container network I/O

**Alerts:**
- Email notifications (SMTP)
- Mobile app push (iOS/Android)
- Webhooks for custom integrations
- Acknowledge/silence in dashboard

---

## Security Hardening Applied

✅ SSH key-only authentication  
✅ SSH port change (configurable)  
✅ UFW firewall (deny by default)  
✅ Fail2Ban (brute force protection)  
✅ Kernel hardening (SYN cookies, redirect protection)  
✅ Automatic security updates  

---

## Next Steps After Setup

1. **Deploy monitoring parent** on Azure
2. **Enroll existing hosts** (Pterodactyl + WHMCS)
3. **Configure alerts** (email + mobile)
4. **Provision wings nodes** as needed
5. **Monitor baseline** and adjust thresholds
6. **Setup backup** of configurations

---

## Getting Help

1. **Script fails?** Check [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
2. **Alerts not working?** See [docs/ALERT-RUNBOOK.md](docs/ALERT-RUNBOOK.md)
3. **Wings won't connect?** See [docs/WINGS-PROVISIONING.md](docs/WINGS-PROVISIONING.md)
4. **Need to scale?** See [docs/COMPLETE-SETUP.md](docs/COMPLETE-SETUP.md) Phase 5

---

## Testing Checklist

After setup, verify:

- [ ] Parent container running: `docker ps | grep netdata-parent`
- [ ] Parent accessible: `curl -s https://<ip>:19999/api/v1/info`
- [ ] Children connected: Check Netdata Cloud dashboard
- [ ] Alerts firing: Test from dashboard
- [ ] Mobile app working: Install app, add server, get notification
- [ ] Wings nodes provisioning: Create test server via panel
- [ ] Security hardening: Try SSH with password (should fail)
- [ ] Firewall rules: Check UFW status
- [ ] Fail2Ban active: Check fail2ban-client status
- [ ] Auto-updates enabled: Check unattended-upgrades status

---

## Environment Variables

For provisioning scripts, set before running:

```bash
export PANEL_URL=https://panel.pexnode.com
export NODE_ID=1
export WINGS_API_KEY=ptla_xxxxx
export NETDATA_TOKEN=abc123
export SSH_PORT=2222
```

Or pass as command arguments.

---

## Common Issues (Quick Fix)

| Problem | Fix |
|---------|-----|
| Parent won't start | Check port 19999 not in use; 1GB RAM needed |
| Child not connecting | Verify token correct; restart child |
| Alerts not sending | Test SMTP in dashboard; verify password |
| Wings won't start | Check API key valid; node ID exists |
| SSH port changed, can't connect | Use new port; check firewall allows it |
| Out of disk space | `docker system prune -a` |

---

## Platform Ops Integration

**Monitoring repo:** `/home/hakon/git/pexnode_monitoring`

**Cross-system docs:** `/home/hakon/git/pexnode_ops_agent/docs/`

**Link in ops repo:** Reference this monitoring setup in:
- Cross-system incident response runbook
- Node provisioning checklist
- Security hardening baseline

---

## Version Info

- **Netdata:** Latest (auto-updates)
- **Wings:** v1.11.8 (configurable in script)
- **Ubuntu:** 22.04 LTS (recommended)
- **Docker:** 20.10+

---

## Support & Documentation

- Netdata docs: https://learn.netdata.cloud/
- Wings docs: https://pterodactyl.io/community/installation-guides/wings/docker.html
- Pterodactyl API: https://pterodactyl.io/api/overview.html
