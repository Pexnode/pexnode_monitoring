#!/bin/bash
# Move remote files/dirs into a timestamped quarantine folder (non-destructive).
#
# Usage:
#   ./scripts/support/quarantine-path.sh <host_ip> <remote_path> [ssh_port]

set -Eeuo pipefail

HOST_IP="${1:-}"
TARGET_PATH="${2:-}"
SSH_PORT="${3:-22}"
DEPLOY_SSH_USER="${DEPLOY_SSH_USER:-root}"
DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-}"
DEPLOY_SSH_OPTIONS="${DEPLOY_SSH_OPTIONS:- -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new}"

if [[ -z "$HOST_IP" || -z "$TARGET_PATH" ]]; then
  echo "Usage: $0 <host_ip> <remote_path> [ssh_port]"
  exit 1
fi

SSH_ARGS=( -p "$SSH_PORT" )
if [[ -n "$DEPLOY_SSH_KEY" ]]; then
  SSH_ARGS+=( -i "$DEPLOY_SSH_KEY" )
fi
# shellcheck disable=SC2206
SSH_ARGS+=( ${DEPLOY_SSH_OPTIONS} )
REMOTE="${DEPLOY_SSH_USER}@${HOST_IP}"

ssh "${SSH_ARGS[@]}" "$REMOTE" bash -s -- "$TARGET_PATH" << 'EOF'
set -Eeuo pipefail

TARGET_PATH="$1"
if [[ ! -e "$TARGET_PATH" ]]; then
  echo "Path not found: $TARGET_PATH"
  exit 1
fi

STAMP=$(date +%Y%m%d-%H%M%S)
BASE_NAME=$(basename "$TARGET_PATH")
QUAR_DIR="/var/backups/pexnode-quarantine/${STAMP}"
mkdir -p "$QUAR_DIR"

mv "$TARGET_PATH" "$QUAR_DIR/${BASE_NAME}"
echo "Moved to: ${QUAR_DIR}/${BASE_NAME}"
EOF
