#!/bin/bash
# Smoke test for Minecraft install application API endpoints.
#
# Usage:
#   PEXNODE_PANEL_URL=https://panel.pexnode.com \
#   PEXNODE_PTERO_APPLICATION_API_KEY=ptla_xxx \
#   SERVER_ID=123 \
#   ./scripts/support/minecraft-install-endpoints-smoke.sh
#
# Optional:
#   JAVA_PLUGIN_SOURCE=modrinth
#   JAVA_PLUGIN_ID=paper
#   JAVA_PLUGIN_VERSION_ID=<version-id>
#   JAVA_PLUGIN_CHECKSUM_SHA256=<sha256>
#   BEDROCK_ADDON_ID=<id>
#   BEDROCK_FILE_ID=<id>
#   BEDROCK_PACK_TYPE=behavior_pack|resource_pack
#   BEDROCK_UPLOADED_FILE_PATH=/path/to/file.mcpack
#   BEDROCK_UPLOADED_CHECKSUM_SHA256=<sha256>

set -Eeuo pipefail

PANEL_URL="${PEXNODE_PANEL_URL:-}"
API_KEY="${PEXNODE_PTERO_APPLICATION_API_KEY:-}"
SERVER_ID="${SERVER_ID:-}"

JAVA_PLUGIN_SOURCE="${JAVA_PLUGIN_SOURCE:-modrinth}"
JAVA_PLUGIN_ID="${JAVA_PLUGIN_ID:-}"
JAVA_PLUGIN_VERSION_ID="${JAVA_PLUGIN_VERSION_ID:-}"
JAVA_PLUGIN_CHECKSUM_SHA256="${JAVA_PLUGIN_CHECKSUM_SHA256:-}"

BEDROCK_ADDON_ID="${BEDROCK_ADDON_ID:-}"
BEDROCK_FILE_ID="${BEDROCK_FILE_ID:-}"
BEDROCK_PACK_TYPE="${BEDROCK_PACK_TYPE:-}"
BEDROCK_UPLOADED_FILE_PATH="${BEDROCK_UPLOADED_FILE_PATH:-}"
BEDROCK_UPLOADED_CHECKSUM_SHA256="${BEDROCK_UPLOADED_CHECKSUM_SHA256:-}"

if [[ -z "$PANEL_URL" || -z "$API_KEY" || -z "$SERVER_ID" ]]; then
  echo "Missing required env vars: PEXNODE_PANEL_URL, PEXNODE_PTERO_APPLICATION_API_KEY, SERVER_ID"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required"
  exit 1
fi

api_call() {
  local method="$1"
  local path="$2"
  local json_body="${3:-}"

  if [[ -n "$json_body" ]]; then
    curl -sS -X "$method" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Accept: Application/vnd.pterodactyl.v1+json" \
      -H "Content-Type: application/json" \
      "${PANEL_URL}${path}" \
      -d "$json_body"
  else
    curl -sS -X "$method" \
      -H "Authorization: Bearer ${API_KEY}" \
      -H "Accept: Application/vnd.pterodactyl.v1+json" \
      "${PANEL_URL}${path}"
  fi
}

print_section() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

print_section "1) Check server details"
api_call GET "/api/application/servers/${SERVER_ID}" | sed -n '1,120p'

if [[ -n "$JAVA_PLUGIN_ID" && -n "$JAVA_PLUGIN_VERSION_ID" ]]; then
  print_section "2) Java plugin install endpoint"

  java_payload="{\"source\":\"${JAVA_PLUGIN_SOURCE}\",\"plugin_id\":\"${JAVA_PLUGIN_ID}\",\"version_id\":\"${JAVA_PLUGIN_VERSION_ID}\""
  if [[ -n "$JAVA_PLUGIN_CHECKSUM_SHA256" ]]; then
    java_payload+=" ,\"checksum_sha256\":\"${JAVA_PLUGIN_CHECKSUM_SHA256}\""
  fi
  java_payload+="}"

  api_call POST "/api/application/servers/${SERVER_ID}/minecraft/plugins/install" "$java_payload" | sed -n '1,160p'
else
  print_section "2) Java plugin install endpoint"
  echo "Skipped (set JAVA_PLUGIN_ID and JAVA_PLUGIN_VERSION_ID to run this test)"
fi

if [[ -n "$BEDROCK_ADDON_ID" && -n "$BEDROCK_FILE_ID" ]]; then
  print_section "3) Bedrock addon install endpoint"

  bedrock_payload="{\"addonId\":${BEDROCK_ADDON_ID},\"fileId\":${BEDROCK_FILE_ID}"
  if [[ -n "$BEDROCK_PACK_TYPE" ]]; then
    bedrock_payload+=" ,\"packType\":\"${BEDROCK_PACK_TYPE}\""
  fi
  bedrock_payload+="}"

  api_call POST "/api/application/servers/${SERVER_ID}/bedrock/addons/install" "$bedrock_payload" | sed -n '1,160p'
else
  print_section "3) Bedrock addon install endpoint"
  echo "Skipped (set BEDROCK_ADDON_ID and BEDROCK_FILE_ID to run this test)"
fi

if [[ -n "$BEDROCK_UPLOADED_FILE_PATH" ]]; then
  print_section "4) Bedrock uploaded install endpoint"

  uploaded_payload="{\"filePath\":\"${BEDROCK_UPLOADED_FILE_PATH}\""
  if [[ -n "$BEDROCK_PACK_TYPE" ]]; then
    uploaded_payload+=" ,\"packType\":\"${BEDROCK_PACK_TYPE}\""
  fi
  if [[ -n "$BEDROCK_UPLOADED_CHECKSUM_SHA256" ]]; then
    uploaded_payload+=" ,\"checksum_sha256\":\"${BEDROCK_UPLOADED_CHECKSUM_SHA256}\""
  fi
  uploaded_payload+="}"

  api_call POST "/api/application/servers/${SERVER_ID}/bedrock/addons/install-uploaded" "$uploaded_payload" | sed -n '1,200p'
else
  print_section "4) Bedrock uploaded install endpoint"
  echo "Skipped (set BEDROCK_UPLOADED_FILE_PATH to run this test)"
fi

echo
echo "Smoke test complete"
