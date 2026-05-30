#!/bin/bash
# Enroll a host in Pexnode monitoring
# Usage: ./enroll-host.sh <host_ip> <claim_token> [<claim_url>]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_IP="${1:-}"
CLAIM_TOKEN="${2:-}"
CLAIM_URL="${3:-https://app.netdata.cloud}"

if [[ -z "$HOST_IP" ]] || [[ -z "$CLAIM_TOKEN" ]]; then
  echo "Usage: $0 <host_ip> <claim_token> [<claim_url>]"
  echo ""
  echo "Example:"
  echo "  $0 74.50.65.10 your-claim-token"
  echo "  $0 104.37.190.203 your-claim-token https://app.netdata.cloud"
  echo ""
  echo "Get your claim token from: https://app.netdata.cloud/spaces/overview"
  exit 1
fi

echo "=========================================="
echo "Pexnode Monitoring: Enroll Host"
echo "=========================================="
echo "Host: $HOST_IP"
echo "Claim URL: $CLAIM_URL"
echo ""

# Check SSH access
echo "[1/5] Testing SSH access to $HOST_IP..."
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes root@"$HOST_IP" "echo 'SSH OK'" &>/dev/null; then
  echo "❌ SSH access failed to root@$HOST_IP"
  echo "   Check:"
  echo "   - Host is reachable"
  echo "   - SSH key is configured in ~/.ssh/config or DEPLOY_SSH_KEY"
  echo "   - Root login is enabled"
  exit 1
fi
echo "✅ SSH access OK"

# Check Docker on host
echo "[2/5] Checking Docker on $HOST_IP..."
if ! ssh root@"$HOST_IP" "docker ps" &>/dev/null; then
  echo "⚠️  Docker not found, installing..."
  ssh root@"$HOST_IP" < "$SCRIPT_DIR/install-docker.sh"
fi
echo "✅ Docker is ready"

# Generate hostname
HOSTNAME=$(ssh root@"$HOST_IP" "hostname -f 2>/dev/null || hostname" | tr -d '\r')
echo "[3/5] Host hostname: $HOSTNAME"

# Deploy child container
echo "[4/5] Deploying Netdata child container..."
ssh root@"$HOST_IP" bash << DEPLOY_SCRIPT
set -e

# Stop old Netdata child if running
docker stop netdata-child 2>/dev/null || true
docker rm netdata-child 2>/dev/null || true

# Get parent URL from environment or use local
PARENT_URL="\${NETDATA_PARENT_URL:-monitoring-parent.pexnode.internal:19999}"

# Run child container
docker run -d \\
  --name netdata-child \\
  --hostname "$HOSTNAME" \\
  --network host \\
  --cap-add SYS_PTRACE \\
  --cap-add SYS_ADMIN \\
  --security-opt apparmor=unconfined \\
  -e NETDATA_CLAIM_TOKEN="$CLAIM_TOKEN" \\
  -e NETDATA_CLAIM_URL="$CLAIM_URL" \\
  -e NETDATA_CLAIM_ONLY="yes" \\
  -e NETDATA_TELEMETRY="no" \\
  -e DOCKER_HOST=unix:///var/run/docker.sock \\
  -v /etc/os-release:/host/etc/os-release:ro \\
  -v /proc:/host/proc:ro \\
  -v /sys:/host/sys:ro \\
  -v /var/run/docker.sock:/var/run/docker.sock:ro \\
  -v /etc/timezone:/etc/timezone:ro \\
  netdata/netdata:latest

echo "Netdata child started"
sleep 3

# Verify container is running
if ! docker ps | grep -q netdata-child; then
  echo "❌ Netdata child failed to start"
  docker logs netdata-child
  exit 1
fi

echo "✅ Netdata child is running"

DEPLOY_SCRIPT

echo "✅ Child container deployed"

# Setup auto-enrollment on reboot
echo "[5/5] Setting up auto-enrollment..."
ssh root@"$HOST_IP" bash << AUTO_SCRIPT
set -e

# Create enrollment script
mkdir -p /opt/pexnode-monitoring
cat > /opt/pexnode-monitoring/enroll-child.sh << 'EOF'
#!/bin/bash
# Auto-enroll Netdata child on host boot
CLAIM_TOKEN="$CLAIM_TOKEN"
CLAIM_URL="$CLAIM_URL"
HOSTNAME=\$(hostname -f 2>/dev/null || hostname)

docker stop netdata-child 2>/dev/null || true
docker rm netdata-child 2>/dev/null || true

docker run -d \\
  --name netdata-child \\
  --hostname "\$HOSTNAME" \\
  --network host \\
  --cap-add SYS_PTRACE \\
  --cap-add SYS_ADMIN \\
  --security-opt apparmor=unconfined \\
  -e NETDATA_CLAIM_TOKEN="\$CLAIM_TOKEN" \\
  -e NETDATA_CLAIM_URL="\$CLAIM_URL" \\
  -e NETDATA_CLAIM_ONLY="yes" \\
  -e NETDATA_TELEMETRY="no" \\
  -e DOCKER_HOST=unix:///var/run/docker.sock \\
  -v /etc/os-release:/host/etc/os-release:ro \\
  -v /proc:/host/proc:ro \\
  -v /sys:/host/sys:ro \\
  -v /var/run/docker.sock:/var/run/docker.sock:ro \\
  -v /etc/timezone:/etc/timezone:ro \\
  netdata/netdata:latest
EOF

chmod +x /opt/pexnode-monitoring/enroll-child.sh

# Create systemd service for auto-start
cat > /etc/systemd/system/pexnode-netdata-child.service << 'EOF'
[Unit]
Description=Pexnode Netdata Child Agent
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=exec
ExecStart=/opt/pexnode-monitoring/enroll-child.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable pexnode-netdata-child.service
systemctl start pexnode-netdata-child.service

echo "Auto-enrollment configured"

AUTO_SCRIPT

echo "✅ Auto-enrollment systemd service installed"

# Success
echo ""
echo "=========================================="
echo "✅ Host enrolled successfully!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Access dashboard: https://app.netdata.cloud"
echo "2. Configure alerts in dashboard"
echo "3. Install Netdata mobile app for push notifications"
echo ""
echo "To view logs on the host:"
echo "  ssh root@$HOST_IP docker logs -f netdata-child"
echo ""
