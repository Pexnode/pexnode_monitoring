# Quick Start (5 Minutes)

For the impatient. Full docs: [DEPLOYMENT-GUIDE.md](DEPLOYMENT-GUIDE.md)

## 1. Get Netdata Token (1 min)

```
→ https://app.netdata.cloud
→ Sign up (free tier)
→ Spaces → Settings → Nodes & Agents
→ Copy "Claim Token"
```

## 2. Deploy Parent on Azure (1 min)

```bash
cd azure
cp .env.template .env.local
# Edit .env.local, paste token
docker-compose up -d
# Get IP: docker ps -q | xargs docker inspect -f '{{.NetworkSettings.IPAddress}}'
```

**Access:** `https://<ip>:19999`

## 3. Enroll Hosts (2 min)

```bash
./scripts/enroll-host.sh 74.50.65.10 <your-token>
./scripts/enroll-host.sh 104.37.190.203 <your-token>
```

## 4. Verify in Dashboard (1 min)

```
→ https://app.netdata.cloud
→ You should see 3 nodes appearing
→ Wait 30-60 sec for metrics
```

## Done! 🎉

Now:
- **Alerts**: See [ALERT-RUNBOOK.md](docs/ALERT-RUNBOOK.md)
- **Auto-enroll new servers**: See [AUTO-ENROLLMENT.md](docs/AUTO-ENROLLMENT.md)
- **Troubleshooting**: See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## Monitoring Active

You now have:
- ✅ CPU, RAM, Disk on both hosts
- ✅ Per-container metrics (Wings)
- ✅ Network I/O
- ✅ Alerts on critical metrics
