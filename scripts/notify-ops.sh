#!/bin/bash
# notify-ops.sh — Send an operational alert to the ops team
#
# Used by create-cloud-node.sh to notify when a new region is provisioned
# and a dedicated server should be ordered.
#
# Usage:
#   scripts/notify-ops.sh <subject> <body>
#
# Output methods (uses all that are configured):
#   1. Always: writes to config/provisioning-alerts.log
#   2. Email:  if ALERT_EMAIL + MAIL_USER + MAIL_PASSWORD + MAIL_SMTP_HOST are set
#   3. Webhook: if ALERT_WEBHOOK_URL is set (Discord/Slack/custom)
#
# Required env (at least one notification method):
#   ALERT_EMAIL        — recipient email address
#   MAIL_USER          — SMTP username (e.g. ops@pexnode.com)
#   MAIL_PASSWORD      — SMTP password
#   MAIL_SMTP_HOST     — SMTP server (e.g. mail.pexnode.com)
#   ALERT_WEBHOOK_URL  — Discord/Slack/custom webhook URL

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── load env ──────────────────────────────────────────────────────────────────

[[ -f "$HOME/.config/pexnode/env" ]] && source "$HOME/.config/pexnode/env"
[[ -f "$REPO_ROOT/.env.local" ]] && source "$REPO_ROOT/.env.local"

# ── args ──────────────────────────────────────────────────────────────────────

SUBJECT="${1:?Usage: notify-ops.sh <subject> <body>}"
BODY="${2:?missing body}"
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M UTC")

LOG_FILE="${REPO_ROOT}/config/provisioning-alerts.log"

# ── always: log to file ───────────────────────────────────────────────────────

{
  echo "════════════════════════════════════════"
  echo "  ${TIMESTAMP}"
  echo "  ${SUBJECT}"
  echo "────────────────────────────────────────"
  echo "${BODY}"
  echo ""
} >> "$LOG_FILE"

echo "[notify-ops] Alert logged to config/provisioning-alerts.log"

# ── email via SMTP ────────────────────────────────────────────────────────────

if [[ -n "${ALERT_EMAIL:-}" && -n "${MAIL_USER:-}" && -n "${MAIL_PASSWORD:-}" && -n "${MAIL_SMTP_HOST:-}" ]]; then

  MAIL_PORT="${MAIL_SMTP_PORT:-587}"

  # Build RFC 2822 message
  EMAIL_BODY=$(cat <<EOF
From: Pexnode Ops <${MAIL_USER}>
To: ${ALERT_EMAIL}
Subject: [Pexnode Ops] ${SUBJECT}
Date: ${TIMESTAMP}
Content-Type: text/plain; charset=UTF-8

${BODY}

---
Sent by notify-ops.sh on $(hostname) at ${TIMESTAMP}
EOF
)

  # Send via curl SMTP (no local mail server needed)
  if curl -s \
    --url "smtp://${MAIL_SMTP_HOST}:${MAIL_PORT}" \
    --ssl-reqd \
    --user "${MAIL_USER}:${MAIL_PASSWORD}" \
    --mail-from "${MAIL_USER}" \
    --mail-rcpt "${ALERT_EMAIL}" \
    --upload-file - <<< "$EMAIL_BODY" \
    >/dev/null 2>&1; then
    echo "[notify-ops] Email sent to ${ALERT_EMAIL}"
  else
    echo "[notify-ops] Warning: email send failed (SMTP). Alert is still in log file." >&2
  fi
else
  if [[ -z "${ALERT_EMAIL:-}" ]]; then
    echo "[notify-ops] ALERT_EMAIL not set — skipping email."
  else
    echo "[notify-ops] MAIL_USER/MAIL_PASSWORD/MAIL_SMTP_HOST not set — skipping email."
  fi
fi

# ── webhook (Discord / Slack / custom) ───────────────────────────────────────

if [[ -n "${ALERT_WEBHOOK_URL:-}" ]]; then

  # Detect format: Discord uses "content", Slack uses "text"
  # Default to Discord format — works with most webhook-capable tools
  webhook_body=$(python3 -c "
import json, sys
subject = sys.argv[1]
body = sys.argv[2]
timestamp = sys.argv[3]

# Try Discord format (embeds)
payload = {
    'username': 'Pexnode Ops',
    'embeds': [{
        'title': subject,
        'description': body,
        'color': 16744272,  # orange
        'footer': {'text': timestamp}
    }]
}
print(json.dumps(payload))
" "$SUBJECT" "$BODY" "$TIMESTAMP")

  if curl -s -X POST \
    -H "Content-Type: application/json" \
    -d "$webhook_body" \
    "${ALERT_WEBHOOK_URL}" \
    >/dev/null 2>&1; then
    echo "[notify-ops] Webhook notification sent"
  else
    echo "[notify-ops] Warning: webhook send failed. Alert is still in log file." >&2
  fi
fi
