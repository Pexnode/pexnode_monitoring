#!/bin/bash
# Auto-enrollment hook for new Pexnode servers
# Deploy this to new servers during provisioning
# This script checks if Netdata is enrolled and enrolls if not

set -Eeuo pipefail

CLAIM_TOKEN="${NETDATA_CLAIM_TOKEN:-}"
CLAIM_URL="${NETDATA_CLAIM_URL:-https://app.netdata.cloud}"
NETDATA_IMAGE="${NETDATA_IMAGE:-netdata/netdata:latest}"

if [[ -z "$CLAIM_TOKEN" ]]; then
  echo "[monitoring] NETDATA_CLAIM_TOKEN not set, skipping auto-enrollment"
  exit 0
fi

HOSTNAME=$(hostname -f 2>/dev/null || hostname)

echo "[monitoring] Ensuring enrollment for server: $HOSTNAME"

if ! command -v docker >/dev/null 2>&1; then
  echo "[monitoring] Docker not found, installing..."
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  rm -f /tmp/get-docker.sh
fi

systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker

if docker ps --format '{{.Names}}' | grep -qx 'netdata-child'; then
  echo "[monitoring] netdata-child already running"
  exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -qx 'netdata-child'; then
  echo "[monitoring] Starting existing netdata-child container"
  docker start netdata-child >/dev/null
  exit 0
fi

docker pull "$NETDATA_IMAGE" >/dev/null 2>&1 || true

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
)

if [[ -f /etc/timezone ]]; then
  docker_args+=( -v /etc/timezone:/etc/timezone:ro )
elif [[ -f /etc/localtime ]]; then
  docker_args+=( -v /etc/localtime:/etc/localtime:ro )
fi

docker_args+=( "$NETDATA_IMAGE" )

docker "${docker_args[@]}"

echo "[monitoring] Netdata child enrolled"
