#!/bin/bash
# Remote deployment entrypoint from this repo.
# It uploads and runs provision-wings-node.sh on a target host safely.
#
# Usage:
#   ./scripts/deploy-wing-host.sh <target_ip> <node_id> [ssh_port]
#
# Required env vars:
#   PANEL_URL
#   WINGS_API_KEY
# Optional env vars:
#   NETDATA_TOKEN
#   DEPLOY_SSH_USER (default root)
#   DEPLOY_SSH_KEY
#   DEPLOY_SSH_OPTIONS
#   REMOTE_SSH_PORT (default 22)

set -Eeuo pipefail

TARGET_IP="${1:-}"
NODE_ID="${2:-}"
HARDENED_SSH_PORT="${3:-2222}"

PANEL_URL="${PANEL_URL:-https://panel.pexnode.com}"
WINGS_API_KEY="${WINGS_API_KEY:-}"
NETDATA_TOKEN="${NETDATA_TOKEN:-}"

DEPLOY_SSH_USER="${DEPLOY_SSH_USER:-root}"
REMOTE_SSH_PORT="${REMOTE_SSH_PORT:-22}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-}"
DEPLOY_SSH_OPTIONS="${DEPLOY_SSH_OPTIONS:- -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new}"

if [[ -z "$TARGET_IP" || -z "$NODE_ID" || -z "$WINGS_API_KEY" ]]; then
  echo "Usage: PANEL_URL=... WINGS_API_KEY=... NETDATA_TOKEN=... $0 <target_ip> <node_id> [ssh_port]"
  exit 1
fi

LOCK_DIR="$(pwd)/.locks"
mkdir -p "$LOCK_DIR"
LOCK_FILE="$LOCK_DIR/deploy-${TARGET_IP}.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Another deployment is already running for ${TARGET_IP}"
  exit 1
fi

SSH_ARGS=( -p "$REMOTE_SSH_PORT" )
if [[ -n "$DEPLOY_SSH_KEY" ]]; then
  SSH_ARGS+=( -i "$DEPLOY_SSH_KEY" )
fi
# shellcheck disable=SC2206
SSH_ARGS+=( ${DEPLOY_SSH_OPTIONS} )

REMOTE="${DEPLOY_SSH_USER}@${TARGET_IP}"
REMOTE_WORKDIR="/tmp/pexnode-monitoring-deploy"

retry_ssh() {
  local tries=0
  local max=4
  until ssh "${SSH_ARGS[@]}" "$REMOTE" "echo ping" >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [[ "$tries" -ge "$max" ]]; then
      echo "SSH connectivity failed to ${REMOTE}"
      return 1
    fi
    sleep 3
  done
}

retry_ssh

echo "Preparing remote workspace on ${TARGET_IP}"
ssh "${SSH_ARGS[@]}" "$REMOTE" "mkdir -p ${REMOTE_WORKDIR}"

echo "Uploading scripts"
scp "${SSH_ARGS[@]}" ./scripts/provision-wings-node.sh "$REMOTE:${REMOTE_WORKDIR}/provision-wings-node.sh"
scp "${SSH_ARGS[@]}" ./scripts/setup-host-maintenance.sh "$REMOTE:${REMOTE_WORKDIR}/setup-host-maintenance.sh"

echo "Running remote deployment with lock"
ssh "${SSH_ARGS[@]}" "$REMOTE" bash -s -- "$PANEL_URL" "$NODE_ID" "$WINGS_API_KEY" "$NETDATA_TOKEN" "$HARDENED_SSH_PORT" "$REMOTE_WORKDIR" << 'EOF'
set -Eeuo pipefail

PANEL_URL="$1"
NODE_ID="$2"
WINGS_API_KEY="$3"
NETDATA_TOKEN="$4"
HARDENED_SSH_PORT="$5"
REMOTE_WORKDIR="$6"

mkdir -p /var/lock
exec 8>/var/lock/pexnode-wings-provision.lock
flock -n 8 || { echo "Remote provision lock is busy"; exit 1; }

chmod +x "${REMOTE_WORKDIR}/provision-wings-node.sh" "${REMOTE_WORKDIR}/setup-host-maintenance.sh"

"${REMOTE_WORKDIR}/provision-wings-node.sh" "$PANEL_URL" "$NODE_ID" "$WINGS_API_KEY" "$NETDATA_TOKEN" "$HARDENED_SSH_PORT"
"${REMOTE_WORKDIR}/setup-host-maintenance.sh"

echo "Remote deployment finished"
EOF

echo "Deployment completed for ${TARGET_IP}"
if [[ "$HARDENED_SSH_PORT" != "$REMOTE_SSH_PORT" ]]; then
  echo "SSH port changed from ${REMOTE_SSH_PORT} to ${HARDENED_SSH_PORT}; use the new port for next connections."
fi
