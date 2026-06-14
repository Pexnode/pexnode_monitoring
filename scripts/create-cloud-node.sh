#!/bin/bash
# create-cloud-node.sh — Provision a new Wings node in a region on demand
#
# Full chain:
#   1. Read regions.conf to resolve provider/location/plan/label
#   2. Build cloud-init user-data (Docker + Wings deps)
#   3. Create VPS via cloud provider API (Hetzner or Vultr)
#   4. Wait for VPS to be active and reachable via SSH
#   5. Create Pterodactyl node record via Application API
#   6. Fetch Wings token from panel → inject into VPS via deploy-wing-host.sh
#   7. Wait for Wings to connect to panel
#   8. Create port allocations on the new node
#   9. Create DNS record: wings-<region>.pexnode.com
#  10. Append node record to config/nodes.state
#  11. Send ops alert: order dedicated server now
#
# Usage:
#   ./scripts/create-cloud-node.sh <region_id> [--dry-run]
#
# Required env:
#   HETZNER_API_TOKEN     (if region uses hetzner)
#   HETZNER_SSH_KEY_ID    (if region uses hetzner)
#   VULTR_API_TOKEN       (if region uses vultr)
#   VULTR_SSH_KEY_ID      (if region uses vultr)
#   PEXNODE_PANEL_URL
#   PEXNODE_PTERO_APPLICATION_API_KEY
#   DEPLOY_SSH_KEY
#   NETDATA_TOKEN         (optional — for monitoring enrollment)
#   DOMENESHOP_TOKEN      (optional — for DNS record)
#   DOMENESHOP_SECRET     (optional — for DNS record)
#   ALERT_EMAIL           (optional — ops notification email)
#   ALERT_WEBHOOK_URL     (optional — Discord/Slack webhook)
#
# Load env: source scripts/load-env.sh  OR  source ~/.config/pexnode/env

set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)] ⚠${NC} $*"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)] ✗${NC} $*" >&2; }

on_error() {
  err "create-cloud-node.sh failed at line $1 (exit $?)"
  err "Check above for details. VPS may have been created but node not registered."
  err "Clean up manually if needed or re-run after fixing the issue."
}
trap 'on_error $LINENO' ERR

# ── args ─────────────────────────────────────────────────────────────────────

REGION_ID="${1:-}"
DRY_RUN=false
if [[ "${2:-}" == "--dry-run" ]] || [[ "${REGION_ID}" == "--dry-run" ]]; then
  DRY_RUN=true
  [[ "${REGION_ID}" == "--dry-run" ]] && REGION_ID="${2:-}"
fi

if [[ -z "$REGION_ID" ]]; then
  echo "Usage: $0 <region_id> [--dry-run]"
  echo ""
  echo "Available regions (from config/regions.conf):"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  grep -v '^#' "${SCRIPT_DIR}/../config/regions.conf" | grep -v '^$' | awk '{printf "  %-20s %s\n", $1, $7" "$8" "$9}'
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── load env ─────────────────────────────────────────────────────────────────

[[ -f "$HOME/.config/pexnode/env" ]] && source "$HOME/.config/pexnode/env"
[[ -f "$REPO_ROOT/.env.local" ]] && source "$REPO_ROOT/.env.local"

# ── resolve region config ─────────────────────────────────────────────────────

REGIONS_CONF="${REPO_ROOT}/config/regions.conf"
if [[ ! -f "$REGIONS_CONF" ]]; then
  err "regions.conf not found at ${REGIONS_CONF}"
  exit 1
fi

region_line=$(grep -v '^#' "$REGIONS_CONF" | grep -v '^$' | awk -v r="$REGION_ID" '$1 == r')
if [[ -z "$region_line" ]]; then
  err "Region '${REGION_ID}' not found in regions.conf"
  err "Available: $(grep -v '^#' "$REGIONS_CONF" | grep -v '^$' | awk '{print $1}' | tr '\n' ' ')"
  exit 1
fi

PROVIDER=$(echo "$region_line"          | awk '{print $2}')
LOCATION=$(echo "$region_line"          | awk '{print $3}')
SERVER_TYPE=$(echo "$region_line"       | awk '{print $4}')
ALLOC_START=$(echo "$region_line"       | awk '{print $5}')
ALLOC_END=$(echo "$region_line"         | awk '{print $6}')
CUSTOMER_LABEL=$(echo "$region_line"    | awk '{print $7}' | tr '-' ' ')
DEDICATED_REC=$(echo "$region_line"     | awk '{print $8}' | tr '-' ' ')
# Legacy fallback for REGION_DESC (used in display only)
REGION_DESC="${CUSTOMER_LABEL}"

# ── validate required env ─────────────────────────────────────────────────────

MISSING=()
[[ -z "${PEXNODE_PANEL_URL:-}" ]]                    && MISSING+=("PEXNODE_PANEL_URL")
[[ -z "${PEXNODE_PTERO_APPLICATION_API_KEY:-}" ]]    && MISSING+=("PEXNODE_PTERO_APPLICATION_API_KEY")
[[ -z "${DEPLOY_SSH_KEY:-}" ]]                       && MISSING+=("DEPLOY_SSH_KEY")

if [[ "$PROVIDER" == "hetzner" ]]; then
  [[ -z "${HETZNER_API_TOKEN:-}" ]]   && MISSING+=("HETZNER_API_TOKEN")
  [[ -z "${HETZNER_SSH_KEY_ID:-}" ]]  && MISSING+=("HETZNER_SSH_KEY_ID")
elif [[ "$PROVIDER" == "vultr" ]]; then
  [[ -z "${VULTR_API_TOKEN:-}" ]]     && MISSING+=("VULTR_API_TOKEN")
  [[ -z "${VULTR_SSH_KEY_ID:-}" ]]    && MISSING+=("VULTR_SSH_KEY_ID")
fi

if [[ "${#MISSING[@]}" -gt 0 ]]; then
  err "Missing required environment variables:"
  for v in "${MISSING[@]}"; do err "  $v"; done
  err "See: pexnode_ops_agent/docs/10-Getting-Started/Env-Variable-Catalog.md"
  exit 1
fi

# ── summary ──────────────────────────────────────────────────────────────────

PANEL_URL="${PEXNODE_PANEL_URL}"
PTERO_API_KEY="${PEXNODE_PTERO_APPLICATION_API_KEY}"
PANEL_HOSTNAME=$(echo "$PANEL_URL" | sed 's|https\?://||')
TIMESTAMP=$(date +%Y%m%d%H%M%S)
VPS_NAME="wings-${REGION_ID}-${TIMESTAMP}"
NODE_NAME="wings-${REGION_ID}"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Pexnode Cloud Node Provisioning${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo "  Region:      ${REGION_ID} (${CUSTOMER_LABEL})"
echo "  Provider:    ${PROVIDER}"
echo "  Location:    ${LOCATION}"
echo "  Server type: ${SERVER_TYPE}"
echo "  Allocations: ${ALLOC_START}–${ALLOC_END}"
echo "  Panel:       ${PANEL_URL}"
echo "  Node name:   ${NODE_NAME}"
echo "  Dedicated:   ${DEDICATED_REC}"
[[ "$DRY_RUN" == "true" ]] && echo -e "  ${YELLOW}DRY RUN — no resources will be created${NC}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  ok "Dry run complete. Config looks valid."
  exit 0
fi

# ── check for existing node ───────────────────────────────────────────────────

NODES_STATE="${REPO_ROOT}/config/nodes.state"
if [[ -f "$NODES_STATE" ]] && grep -q "^${REGION_ID}" "$NODES_STATE" 2>/dev/null; then
  warn "A node for region '${REGION_ID}' already exists in nodes.state:"
  grep "^${REGION_ID}" "$NODES_STATE"
  echo ""
  read -r -p "Continue anyway and create an additional node? [y/N] " confirm
  [[ "${confirm,,}" != "y" ]] && { log "Aborted."; exit 0; }
fi

# ── cloud-init user-data ──────────────────────────────────────────────────────
# Pre-installs Docker so Wings provisioning is faster.

USERDATA_FILE=$(mktemp /tmp/pexnode-userdata-XXXXXX.sh)
trap 'rm -f "$USERDATA_FILE"' EXIT

cat > "$USERDATA_FILE" << 'USERDATA'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# Basic hardening and Docker pre-install
apt-get update -qq
apt-get install -y -qq \
  curl wget git unzip ca-certificates gnupg ufw \
  apt-transport-https software-properties-common

# Docker
curl -fsSL https://get.docker.com | bash

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Open required ports for Wings
ufw allow 22/tcp
ufw allow 2022/tcp
ufw allow 8080/tcp
ufw allow 443/tcp
ufw --force enable

echo "cloud-init complete" >> /var/log/pexnode-cloud-init.log
USERDATA

# ── step 1: create VPS ────────────────────────────────────────────────────────

log "Step 1/8: Creating VPS with ${PROVIDER}..."

VPS_ID=""
VPS_IP=""

if [[ "$PROVIDER" == "hetzner" ]]; then
  result=$(bash "${SCRIPT_DIR}/hetzner-api.sh" server-create \
    "$VPS_NAME" "$LOCATION" "$SERVER_TYPE" "$HETZNER_SSH_KEY_ID" "$USERDATA_FILE")
  VPS_ID=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['server']['id'])")
  ok "Hetzner server created: ID=${VPS_ID}"

elif [[ "$PROVIDER" == "vultr" ]]; then
  result=$(bash "${SCRIPT_DIR}/vultr-api.sh" instance-create \
    "$VPS_NAME" "$LOCATION" "$SERVER_TYPE" "$VULTR_SSH_KEY_ID" "$USERDATA_FILE")
  VPS_ID=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['instance']['id'])")
  ok "Vultr instance created: ID=${VPS_ID}"
fi

# ── step 2: wait for VPS to be active ────────────────────────────────────────

log "Step 2/8: Waiting for VPS to become active (up to 5 min)..."

MAX_WAIT=300
WAITED=0
POLL_INTERVAL=10

while [[ $WAITED -lt $MAX_WAIT ]]; do
  if [[ "$PROVIDER" == "hetzner" ]]; then
    status=$(bash "${SCRIPT_DIR}/hetzner-api.sh" get "/servers/${VPS_ID}" | \
      python3 -c "import json,sys; s=json.load(sys.stdin)['server']; print(s['status'], s['public_net']['ipv4']['ip'])" 2>/dev/null || echo "pending ")
    vps_status=$(echo "$status" | awk '{print $1}')
    VPS_IP=$(echo "$status" | awk '{print $2}')
    [[ "$vps_status" == "running" && -n "$VPS_IP" && "$VPS_IP" != "0.0.0.0" ]] && break

  elif [[ "$PROVIDER" == "vultr" ]]; then
    status=$(bash "${SCRIPT_DIR}/vultr-api.sh" get "/instances/${VPS_ID}" | \
      python3 -c "import json,sys; i=json.load(sys.stdin)['instance']; print(i['status'], i['main_ip'])" 2>/dev/null || echo "pending ")
    vps_status=$(echo "$status" | awk '{print $1}')
    VPS_IP=$(echo "$status" | awk '{print $2}')
    [[ "$vps_status" == "active" && -n "$VPS_IP" && "$VPS_IP" != "0.0.0.0" ]] && break
  fi

  echo "  status=${vps_status} ip=${VPS_IP:-pending} waited=${WAITED}s"
  sleep $POLL_INTERVAL
  WAITED=$((WAITED + POLL_INTERVAL))
done

if [[ -z "$VPS_IP" ]] || [[ "$VPS_IP" == "0.0.0.0" ]]; then
  err "VPS did not get an IP after ${MAX_WAIT}s. ID=${VPS_ID}"
  exit 1
fi

ok "VPS is active: IP=${VPS_IP}"

# ── step 3: wait for SSH ──────────────────────────────────────────────────────

log "Step 3/8: Waiting for SSH to be available on ${VPS_IP}..."

SSH_ARGS=( -i "$DEPLOY_SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new )
SSH_WAIT=0
SSH_MAX=180

while [[ $SSH_WAIT -lt $SSH_MAX ]]; do
  if ssh "${SSH_ARGS[@]}" "root@${VPS_IP}" "echo ok" >/dev/null 2>&1; then
    break
  fi
  echo "  SSH not ready yet... waited=${SSH_WAIT}s"
  sleep 10
  SSH_WAIT=$((SSH_WAIT + 10))
done

if ! ssh "${SSH_ARGS[@]}" "root@${VPS_IP}" "echo ok" >/dev/null 2>&1; then
  err "SSH not available on ${VPS_IP} after ${SSH_MAX}s"
  exit 1
fi

ok "SSH is available"

# ── step 4: create Pterodactyl node ──────────────────────────────────────────

log "Step 4/8: Creating Pterodactyl node record..."

NODE_FQDN="${VPS_IP}"
# Use a DNS name if we have Domeneshop configured
if [[ -n "${DOMENESHOP_TOKEN:-}" ]]; then
  NODE_FQDN="wings-${REGION_ID}.pexnode.com"
fi

ptero_node_body=$(python3 -c "
import json
print(json.dumps({
    'name': '${NODE_NAME}',
    'location_id': 1,
    'fqdn': '${NODE_FQDN}',
    'scheme': 'https',
    'memory': 14000,
    'memory_overallocate': 0,
    'disk': 80000,
    'disk_overallocate': 0,
    'upload_size': 1024,
    'daemon_sftp': 2022,
    'daemon_listen': 8080,
}))
")

ptero_node=$(curl -s -X POST \
  -H "Authorization: Bearer ${PTERO_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "$ptero_node_body" \
  "${PANEL_URL}/api/application/nodes")

PTERO_NODE_ID=$(echo "$ptero_node" | python3 -c "import json,sys; print(json.load(sys.stdin)['attributes']['id'])")

if [[ -z "$PTERO_NODE_ID" ]]; then
  err "Failed to create Pterodactyl node. Response:"
  echo "$ptero_node" >&2
  exit 1
fi

ok "Pterodactyl node created: ID=${PTERO_NODE_ID}"

# ── step 5: fetch Wings token from panel ─────────────────────────────────────

log "Step 5/8: Fetching Wings configuration from panel..."

wings_config=$(curl -s \
  -H "Authorization: Bearer ${PTERO_API_KEY}" \
  -H "Accept: application/json" \
  "${PANEL_URL}/api/application/nodes/${PTERO_NODE_ID}/configuration")

WINGS_TOKEN=$(echo "$wings_config" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['token'])
" 2>/dev/null)

if [[ -z "$WINGS_TOKEN" ]]; then
  err "Could not extract Wings token from panel config. Response:"
  echo "$wings_config" >&2
  exit 1
fi

ok "Wings token obtained"

# ── step 6: provision Wings on the VPS ───────────────────────────────────────

log "Step 6/8: Provisioning Wings on ${VPS_IP}..."

PANEL_URL="$PANEL_URL" \
WINGS_API_KEY="$WINGS_TOKEN" \
NETDATA_TOKEN="${NETDATA_TOKEN:-}" \
DEPLOY_SSH_KEY="$DEPLOY_SSH_KEY" \
DEPLOY_SSH_USER="root" \
bash "${SCRIPT_DIR}/deploy-wing-host.sh" "$VPS_IP" "$PTERO_NODE_ID"

ok "Wings deployed"

# ── step 7: wait for Wings to connect ────────────────────────────────────────

log "Step 7/8: Waiting for Wings to connect to panel (up to 3 min)..."

WINGS_WAIT=0
WINGS_MAX=180

while [[ $WINGS_WAIT -lt $WINGS_MAX ]]; do
  node_status=$(curl -s \
    -H "Authorization: Bearer ${PTERO_API_KEY}" \
    -H "Accept: application/json" \
    "${PANEL_URL}/api/application/nodes/${PTERO_NODE_ID}" | \
    python3 -c "import json,sys; print('ok')" 2>/dev/null || echo "pending")

  # Wings doesn't report a "connected" field via API — check via HTTP health
  if curl -s --max-time 5 "http://${VPS_IP}:8080" >/dev/null 2>&1; then
    break
  fi

  echo "  Wings not responding yet... waited=${WINGS_WAIT}s"
  sleep 10
  WINGS_WAIT=$((WINGS_WAIT + 10))
done

if ! curl -s --max-time 5 "http://${VPS_IP}:8080" >/dev/null 2>&1; then
  warn "Wings HTTP health check not responding after ${WINGS_MAX}s."
  warn "Wings may still be starting. Check: curl http://${VPS_IP}:8080"
  warn "Continuing with allocation creation..."
fi

ok "Wings is responding"

# ── step 8: create port allocations ──────────────────────────────────────────

log "Step 8/8: Creating port allocations ${ALLOC_START}–${ALLOC_END}..."

# Pterodactyl Application API accepts batches of allocations
alloc_body=$(python3 -c "
import json
ports = list(range(${ALLOC_START}, ${ALLOC_END} + 1))
# API accepts up to 1000 per request; send all at once for our 500-port range
print(json.dumps({'ip': '${VPS_IP}', 'ports': [str(p) for p in ports]}))
")

alloc_result=$(curl -s -X POST \
  -H "Authorization: Bearer ${PTERO_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "$alloc_body" \
  "${PANEL_URL}/api/application/nodes/${PTERO_NODE_ID}/allocations")

ok "Allocations created"

# ── step 9: DNS record (optional) ────────────────────────────────────────────

if [[ -n "${DOMENESHOP_TOKEN:-}" && -n "${DOMENESHOP_SECRET:-}" ]]; then
  log "Step 9: Creating DNS record wings-${REGION_ID}.pexnode.com → ${VPS_IP}..."

  dns_body=$(python3 -c "import json; print(json.dumps({'host': 'wings-${REGION_ID}', 'ttl': 300, 'type': 'A', 'data': '${VPS_IP}'}))")

  dns_result=$(curl -s -X POST \
    -u "${DOMENESHOP_TOKEN}:${DOMENESHOP_SECRET}" \
    -H "Content-Type: application/json" \
    -d "$dns_body" \
    "https://api.domeneshop.no/v0/domains/2227110/dns")

  ok "DNS record created"
else
  warn "DOMENESHOP_TOKEN/SECRET not set — skipping DNS record."
  warn "Node FQDN is set to IP: ${VPS_IP}"
  warn "Update Pterodactyl node manually if you add DNS later."
fi

# ── record state ──────────────────────────────────────────────────────────────

CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "${REGION_ID}	${PROVIDER}	${VPS_ID}	${VPS_IP}	${PTERO_NODE_ID}	${CREATED_AT}" >> "$NODES_STATE"
ok "State recorded in config/nodes.state"

# ── step 10 (final): ops alert — order dedicated server ──────────────────────

DNS_LINE=""
[[ -n "${DOMENESHOP_TOKEN:-}" ]] && DNS_LINE="wings-${REGION_ID}.pexnode.com → ${VPS_IP}"

ALERT_SUBJECT="Ny region aktiv: ${CUSTOMER_LABEL} — bestill dedikert server"
ALERT_BODY="""En ny region er provisjonert og klar for kunder.

Region:       ${CUSTOMER_LABEL} (${REGION_ID})
VPS IP:       ${VPS_IP}
VPS ID:       ${VPS_ID} (${PROVIDER})
Pterodactyl:  Node #${PTERO_NODE_ID}
Allokasjoner: ${ALLOC_START}–${ALLOC_END}
${DNS_LINE:+DNS:          ${DNS_LINE}\n}
Panel-node:   ${PANEL_URL}/admin/nodes/view/${PTERO_NODE_ID}/configuration

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BESTILL DEDIKERT SERVER NÅ:
${DEDICATED_REC}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Kunden er allerede i gang på VPS-en.
Når dedikert server er klar: kjør migrasjon og slett VPS.

Opprettet: ${CREATED_AT}"""

bash "${SCRIPT_DIR}/notify-ops.sh" "$ALERT_SUBJECT" "$ALERT_BODY"

# ── summary ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Node provisioning complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo "  Region:        ${REGION_ID} (${CUSTOMER_LABEL})"
echo "  VPS IP:        ${VPS_IP}"
echo "  VPS ID:        ${VPS_ID} (${PROVIDER})"
echo "  Pterodactyl:   Node #${PTERO_NODE_ID}"
echo "  Allocations:   ${ALLOC_START}–${ALLOC_END}"
[[ -n "${DOMENESHOP_TOKEN:-}" ]] && echo "  DNS:           wings-${REGION_ID}.pexnode.com"
echo ""
echo -e "  ${YELLOW}ACTION REQUIRED: Bestill dedikert server for ${CUSTOMER_LABEL}${NC}"
echo "  ${DEDICATED_REC}"
echo ""
echo "  Panel:  ${PANEL_URL}/admin/nodes/view/${PTERO_NODE_ID}/configuration"
echo ""
