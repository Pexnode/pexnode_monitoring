#!/bin/bash
# Diagnose a Wings host for Minecraft support issues.
# Safe read-only checks only.
#
# Usage:
#   ./scripts/support/minecraft-node-diagnose.sh <host_ip> [ssh_port]

set -Eeuo pipefail

HOST_IP="${1:-}"
SSH_PORT="${2:-22}"
DEPLOY_SSH_USER="${DEPLOY_SSH_USER:-root}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-}"
DEPLOY_SSH_OPTIONS="${DEPLOY_SSH_OPTIONS:- -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new}"

if [[ -z "$HOST_IP" ]]; then
  echo "Usage: $0 <host_ip> [ssh_port]"
  exit 1
fi

SSH_ARGS=( -p "$SSH_PORT" )
if [[ -n "$DEPLOY_SSH_KEY" ]]; then
  SSH_ARGS+=( -i "$DEPLOY_SSH_KEY" )
fi
# shellcheck disable=SC2206
SSH_ARGS+=( ${DEPLOY_SSH_OPTIONS} )
REMOTE="${DEPLOY_SSH_USER}@${HOST_IP}"

echo "=== Pexnode Minecraft Node Diagnose ==="
echo "Host: ${HOST_IP}:${SSH_PORT}"
echo

ssh "${SSH_ARGS[@]}" "$REMOTE" bash -s << 'EOF'
set -Eeuo pipefail

echo "[system] uptime"
uptime || true
echo

echo "[system] disk"
df -h || true
echo

echo "[system] memory"
free -h || true
echo

echo "[wings] service status"
systemctl is-enabled wings 2>/dev/null || true
systemctl is-active wings 2>/dev/null || true
systemctl status wings --no-pager -n 30 2>/dev/null || true
echo

echo "[wings] recent logs"
journalctl -u wings --no-pager -n 80 2>/dev/null || true
echo

echo "[docker] status"
systemctl is-active docker 2>/dev/null || true
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
echo

echo "[monitoring] netdata child"
docker ps --format '{{.Names}}' 2>/dev/null | grep -qx netdata-child && echo "netdata-child running" || echo "netdata-child not running"
echo

echo "[minecraft] containers (name/image hint)"
docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null | grep -Ei 'minecraft|itzg|java|bedrock|server' || true
echo

echo "[network] wings port listener"
ss -ltnp 2>/dev/null | grep -E ':8080|:2022|:25565|:19132' || true
EOF
