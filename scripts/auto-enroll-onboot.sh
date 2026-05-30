#!/bin/bash
# Auto-enrollment hook for new Pexnode servers
# Deploy this to new servers during provisioning
# This script checks if Netdata is enrolled and enrolls if not

CLAIM_TOKEN="${NETDATA_CLAIM_TOKEN:-}"
CLAIM_URL="${NETDATA_CLAIM_URL:-https://app.netdata.cloud}"
PARENT_URL="${NETDATA_PARENT_URL:-}"

if [[ -z "$CLAIM_TOKEN" ]]; then
  echo "⚠️  NETDATA_CLAIM_TOKEN not set, skipping auto-enrollment"
  exit 0
fi

HOSTNAME=$(hostname -f 2>/dev/null || hostname)

echo "Auto-enrolling server: $HOSTNAME"

# Install Docker if needed
if ! command -v docker &> /dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
fi

# Start Docker
systemctl enable docker
systemctl start docker

# Check if Netdata child is already running
if docker ps | grep -q netdata-child; then
  echo "✅ Netdata child already running"
  exit 0
fi

# Remove old container if exists
docker stop netdata-child 2>/dev/null || true
docker rm netdata-child 2>/dev/null || true

# Run Netdata child
docker run -d \
  --name netdata-child \
  --hostname "$HOSTNAME" \
  --network host \
  --cap-add SYS_PTRACE \
  --cap-add SYS_ADMIN \
  --security-opt apparmor=unconfined \
  -e NETDATA_CLAIM_TOKEN="$CLAIM_TOKEN" \
  -e NETDATA_CLAIM_URL="$CLAIM_URL" \
  -e NETDATA_CLAIM_ONLY="yes" \
  -e NETDATA_TELEMETRY="no" \
  -e DOCKER_HOST=unix:///var/run/docker.sock \
  -v /etc/os-release:/host/etc/os-release:ro \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /etc/timezone:/etc/timezone:ro \
  netdata/netdata:latest

echo "✅ Netdata child enrolled"
