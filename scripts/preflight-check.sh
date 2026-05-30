#!/bin/bash
# Operator preflight checks before deploy actions.

set -Eeuo pipefail

echo "=== Pexnode Monitoring Preflight ==="

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing command: $1"
    exit 1
  fi
}

need_cmd bash
need_cmd ssh
need_cmd scp
need_cmd git
need_cmd curl

echo "Commands: OK"

if [[ ! -f ./scripts/deploy-wing-host.sh ]]; then
  echo "Run this from repo root: /home/hakon/git/pexnode_monitoring"
  exit 1
fi

if [[ -z "${WINGS_API_KEY:-}" ]]; then
  echo "WINGS_API_KEY is not set"
  exit 1
fi

if [[ -z "${PANEL_URL:-}" ]]; then
  echo "PANEL_URL not set; defaulting to https://panel.pexnode.com"
fi

echo "Env: OK"

echo "Preflight passed"
