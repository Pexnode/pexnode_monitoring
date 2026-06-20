#!/bin/bash
# Enroll a host in Pexnode monitoring
# Usage: ./enroll-host.sh <host_ip> <claim_token> [<claim_url>]

set -Eeuo pipefail

on_error() {
  local exit_code=$?
  local line_no=$1
  echo "ERROR: enroll-host.sh failed at line ${line_no} (exit ${exit_code})"
  exit "$exit_code"
}

trap 'on_error $LINENO' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_IP="${1:-}"
CLAIM_TOKEN="${2:-}"
CLAIM_URL="${3:-https://app.netdata.cloud}"
NETDATA_IMAGE="${NETDATA_IMAGE:-netdata/netdata:latest}"

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
ssh root@"$HOST_IP" bash -s -- "$CLAIM_TOKEN" "$CLAIM_URL" "$HOSTNAME" "$NETDATA_IMAGE" << 'DEPLOY_SCRIPT'
set -Eeuo pipefail

CLAIM_TOKEN="$1"
CLAIM_URL="$2"
HOSTNAME="$3"
NETDATA_IMAGE="$4"

if docker ps --format '{{.Names}}' | grep -qx 'netdata-child'; then
  echo "netdata-child already running"
  exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -qx 'netdata-child'; then
  echo "starting existing netdata-child container"
  docker start netdata-child >/dev/null
  exit 0
fi

docker pull "$NETDATA_IMAGE" >/dev/null 2>&1 || true

# Ensure config dirs exist on host
mkdir -p /opt/netdata/health.d /opt/netdata/go.d

# Write streaming config (parent FQDN + UUID API key)
cat > /opt/netdata/stream.conf << 'STREAMEOF'
[stream]
    enabled = yes
    destination = pexnode-netdata.norwayeast.azurecontainer.io:19999
    api key = 449c2b8f-8a52-467c-b6e6-2532dfafadc2
    timeout seconds = 60
    send charts matching = *
    buffer size bytes = 1048576
    reconnect delay seconds = 5
STREAMEOF

docker_args=(
  run -d
  --name netdata-child
  --hostname "$HOSTNAME"
  --network host
  --cap-add SYS_PTRACE
  --cap-add SYS_ADMIN
  --security-opt apparmor=unconfined
  -e NETDATA_CLAIM_TOKEN="$CLAIM_TOKEN"
  -e NETDATA_CLAIM_URL="$CLAIM_URL"
  -e NETDATA_CLAIM_ONLY=yes
  -e NETDATA_TELEMETRY=no
  -e DOCKER_HOST=unix:///var/run/docker.sock
  -v /etc/os-release:/host/etc/os-release:ro
  -v /proc:/host/proc:ro
  -v /sys:/host/sys:ro
  -v /var/run/docker.sock:/var/run/docker.sock:ro
  -v /opt/netdata/stream.conf:/etc/netdata/stream.conf:ro
  -v /opt/netdata/health.d:/etc/netdata/health.d:ro
  -v /opt/netdata/go.d:/etc/netdata/go.d:ro
)

if [[ -f /etc/timezone ]]; then
  docker_args+=( -v /etc/timezone:/etc/timezone:ro )
elif [[ -f /etc/localtime ]]; then
  docker_args+=( -v /etc/localtime:/etc/localtime:ro )
fi

docker_args+=( "$NETDATA_IMAGE" )
docker "${docker_args[@]}"

if ! docker ps --format '{{.Names}}' | grep -qx 'netdata-child'; then
  echo "netdata-child failed to start"
  docker logs --tail 60 netdata-child || true
  exit 1
fi

echo "netdata-child deployed"
DEPLOY_SCRIPT

echo "✅ Child container deployed"

# Setup auto-enrollment on reboot
echo "[5/5] Setting up auto-enrollment..."
ssh root@"$HOST_IP" bash -s -- "$CLAIM_TOKEN" "$CLAIM_URL" "$NETDATA_IMAGE" << 'AUTO_SCRIPT'
set -Eeuo pipefail

CLAIM_TOKEN="$1"
CLAIM_URL="$2"
NETDATA_IMAGE="$3"

mkdir -p /opt/pexnode-monitoring

cat > /etc/pexnode-monitoring.env << EOF
CLAIM_TOKEN=$CLAIM_TOKEN
CLAIM_URL=$CLAIM_URL
NETDATA_IMAGE=$NETDATA_IMAGE
EOF
chmod 600 /etc/pexnode-monitoring.env

cat > /opt/pexnode-monitoring/enroll-child.sh << 'EOF'
#!/bin/bash
set -Eeuo pipefail

source /etc/pexnode-monitoring.env
HOSTNAME=$(hostname -f 2>/dev/null || hostname)

if docker ps --format '{{.Names}}' | grep -qx 'netdata-child'; then
  exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -qx 'netdata-child'; then
  docker start netdata-child >/dev/null
  exit 0
fi

docker pull "$NETDATA_IMAGE" >/dev/null 2>&1 || true

mkdir -p /opt/netdata/health.d /opt/netdata/go.d

docker_args=(
  run -d
  --name netdata-child
  --hostname "$HOSTNAME"
  --network host
  --cap-add SYS_PTRACE
  --cap-add SYS_ADMIN
  --security-opt apparmor=unconfined
  -e NETDATA_CLAIM_TOKEN="$CLAIM_TOKEN"
  -e NETDATA_CLAIM_URL="$CLAIM_URL"
  -e NETDATA_CLAIM_ONLY=yes
  -e NETDATA_TELEMETRY=no
  -e DOCKER_HOST=unix:///var/run/docker.sock
  -v /etc/os-release:/host/etc/os-release:ro
  -v /proc:/host/proc:ro
  -v /sys:/host/sys:ro
  -v /var/run/docker.sock:/var/run/docker.sock:ro
  -v /opt/netdata/stream.conf:/etc/netdata/stream.conf:ro
  -v /opt/netdata/health.d:/etc/netdata/health.d:ro
  -v /opt/netdata/go.d:/etc/netdata/go.d:ro
)

if [[ -f /etc/timezone ]]; then
  docker_args+=( -v /etc/timezone:/etc/timezone:ro )
elif [[ -f /etc/localtime ]]; then
  docker_args+=( -v /etc/localtime:/etc/localtime:ro )
fi

docker_args+=( "$NETDATA_IMAGE" )
docker "${docker_args[@]}"
EOF

chmod +x /opt/pexnode-monitoring/enroll-child.sh

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
systemctl restart pexnode-netdata-child.service

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
