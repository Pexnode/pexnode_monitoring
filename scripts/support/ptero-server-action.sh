#!/bin/bash
# Perform safe Pterodactyl server actions for Minecraft support.
#
# Usage:
#   PEXNODE_PANEL_URL=... PEXNODE_PTERO_APPLICATION_API_KEY=... \
#   ./scripts/support/ptero-server-action.sh <server_id_or_uuid> <action> [command]
#
# Actions:
#   start | stop | restart | kill | reinstall | command | details

set -Eeuo pipefail

SERVER_REF="${1:-}"
ACTION="${2:-}"
COMMAND_TEXT="${3:-}"

PANEL_URL="${PEXNODE_PANEL_URL:-}"
APP_KEY="${PEXNODE_PTERO_APPLICATION_API_KEY:-}"
ALLOWED_EGG_IDS="${ALLOWED_EGG_IDS:-1,15}"

if [[ -z "$SERVER_REF" || -z "$ACTION" || -z "$PANEL_URL" || -z "$APP_KEY" ]]; then
  echo "Usage: PEXNODE_PANEL_URL=... PEXNODE_PTERO_APPLICATION_API_KEY=... $0 <server_id_or_uuid> <action> [command]"
  exit 1
fi

api() {
  local method="$1"
  local path="$2"
  local data="${3:-}"

  if [[ -n "$data" ]]; then
    curl -fsSL -X "$method" \
      -H "Authorization: Bearer ${APP_KEY}" \
      -H "Accept: Application/vnd.pterodactyl.v1+json" \
      -H "Content-Type: application/json" \
      "${PANEL_URL}${path}" \
      -d "$data"
  else
    curl -fsSL -X "$method" \
      -H "Authorization: Bearer ${APP_KEY}" \
      -H "Accept: Application/vnd.pterodactyl.v1+json" \
      "${PANEL_URL}${path}"
  fi
}

server_json=$(api GET "/api/application/servers/${SERVER_REF}")

egg_id=$(printf '%s' "$server_json" | sed -n 's/.*"egg"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)
identifier=$(printf '%s' "$server_json" | sed -n 's/.*"identifier"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)
name=$(printf '%s' "$server_json" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)

if [[ -z "$identifier" ]]; then
  echo "Could not resolve server identifier from API response"
  exit 1
fi

if ! echo ",$ALLOWED_EGG_IDS," | grep -q ",${egg_id},"; then
  echo "Refusing action: server egg ${egg_id} is not in allowed Minecraft egg list (${ALLOWED_EGG_IDS})"
  exit 1
fi

case "$ACTION" in
  details)
    echo "$server_json"
    ;;
  start|stop|restart|kill)
    api POST "/api/client/servers/${identifier}/power" "{\"signal\":\"${ACTION}\"}" >/dev/null
    echo "Action ${ACTION} sent to ${name} (${identifier})"
    ;;
  command)
    if [[ -z "$COMMAND_TEXT" ]]; then
      echo "Action 'command' requires third argument"
      exit 1
    fi
    api POST "/api/client/servers/${identifier}/command" "{\"command\":\"${COMMAND_TEXT}\"}" >/dev/null
    echo "Command sent to ${name} (${identifier})"
    ;;
  reinstall)
    api POST "/api/application/servers/${SERVER_REF}/reinstall" >/dev/null
    echo "Reinstall requested for ${name} (${identifier})"
    ;;
  *)
    echo "Unsupported action: ${ACTION}"
    exit 1
    ;;
esac
