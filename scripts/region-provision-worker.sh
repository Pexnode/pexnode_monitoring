#!/bin/bash
# region-provision-worker.sh — Consume the WHMCS regional provisioning queue
#
# Runs on a TRUSTED host (the panel server) that holds the cloud-provider tokens
# and the DEPLOY_SSH_KEY. WHMCS only records provisioning intent in the
# `mod_pexnode_region_queue` table; this worker does the actual work:
#
#   1. Read pending rows from the WHMCS DB (read-only) via whmcs-db.sh
#   2. Validate the region against config/regions.conf (allowlist)
#   3. Per-region lock (flock) so a region is never provisioned twice
#   4. Re-check whether a node already exists (idempotency guard)
#   5. Run create-cloud-node.sh <region> for cold regions
#   6. Complete each waiting service via WHMCS ModuleCreate (whmcs-api.sh)
#   7. Update the queue row status; retry with backoff; alert on final failure
#
# Intended to run from cron on the panel server, e.g.:
#   * * * * * /opt/pexnode_monitoring/scripts/region-provision-worker.sh >> /var/log/pexnode-region-worker.log 2>&1
#
# Required env (load from $HOME/.config/pexnode/env or <repo>/.env.local):
#   WHMCS_SCRIPTS_DIR    — path to pexnode_whmcs/scripts (whmcs-db.sh + whmcs-api.sh)
#   PEXNODE_PANEL_URL
#   PEXNODE_PTERO_APPLICATION_API_KEY
#   DEPLOY_SSH_KEY
#   HETZNER_API_TOKEN / HETZNER_SSH_KEY_ID   (regions on hetzner)
#   VULTR_API_TOKEN / VULTR_SSH_KEY_ID       (regions on vultr)
#   WHMCS_HOST / WHMCS_SSH_USER / WHMCS_SSH_KEY / WHMCS_DB_*  (used by whmcs-db.sh)
#   WHMCS_API_URL / WHMCS_API_IDENTIFIER / WHMCS_API_SECRET   (used by whmcs-api.sh)
#
# Optional env:
#   MAX_ATTEMPTS         — retry attempts before marking failed (default 3)
#   WORKER_DRY_RUN       — if "true", logs actions without provisioning/completing
#
# Exit codes: 0 = run complete (success or nothing to do), non-zero = setup error.

# shellcheck disable=SC1091  # env files are runtime-only and not tracked in the repo
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── load env ──────────────────────────────────────────────────────────────────

[[ -f "$HOME/.config/pexnode/env" ]] && source "$HOME/.config/pexnode/env"
[[ -f "$REPO_ROOT/.env.local" ]] && source "$REPO_ROOT/.env.local"

MAX_ATTEMPTS="${MAX_ATTEMPTS:-3}"
WORKER_DRY_RUN="${WORKER_DRY_RUN:-false}"
REGIONS_CONF="${REPO_ROOT}/config/regions.conf"
LOCK_DIR="${LOCK_DIR:-/tmp}"

log()  { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }
err()  { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] ERROR: $*" >&2; }

# ── global single-flight lock (no overlapping worker runs) ───────────────────

GLOBAL_LOCK="${LOCK_DIR}/pexnode-region-worker.lock"
exec 9>"$GLOBAL_LOCK"
if ! flock -n 9; then
  log "Another worker run is in progress — exiting."
  exit 0
fi

# ── preflight ─────────────────────────────────────────────────────────────────

WHMCS_SCRIPTS_DIR="${WHMCS_SCRIPTS_DIR:-}"
if [[ -z "$WHMCS_SCRIPTS_DIR" ]]; then
  # Best-effort default: sibling checkout next to this repo.
  for guess in \
    "$(dirname "$REPO_ROOT")/pexnode_whmcs/scripts" \
    "/opt/pexnode_whmcs/scripts"; do
    [[ -f "$guess/whmcs-db.sh" ]] && WHMCS_SCRIPTS_DIR="$guess" && break
  done
fi

WHMCS_DB="${WHMCS_SCRIPTS_DIR}/whmcs-db.sh"
WHMCS_API="${WHMCS_SCRIPTS_DIR}/whmcs-api.sh"

if [[ ! -f "$WHMCS_DB" || ! -f "$WHMCS_API" ]]; then
  err "WHMCS scripts not found. Set WHMCS_SCRIPTS_DIR to pexnode_whmcs/scripts."
  err "  Looked for: $WHMCS_DB"
  exit 1
fi

if [[ ! -f "$REGIONS_CONF" ]]; then
  err "regions.conf not found at ${REGIONS_CONF}"
  exit 1
fi

# ── helpers ───────────────────────────────────────────────────────────────────

# Validate a region id against the regions.conf allowlist (active, uncommented).
region_is_valid() {
  local region="$1"
  grep -v '^#' "$REGIONS_CONF" | grep -v '^$' | awk '{print $1}' | grep -qx "$region"
}

# Run a SQL statement against the WHMCS DB. Read or write.
db() {
  bash "$WHMCS_DB" query "$1"
}

# Mark a queue row's status (+ optional error / node id). service_id is an int.
queue_update() {
  local service_id="$1" status="$2" extra="${3:-}"
  local sql="UPDATE mod_pexnode_region_queue SET status='${status}'"
  [[ -n "$extra" ]] && sql+=", ${extra}"
  sql+=" WHERE service_id=${service_id};"
  if [[ "$WORKER_DRY_RUN" == "true" ]]; then
    log "[dry-run] would run: ${sql}"
    return 0
  fi
  db "$sql" >/dev/null
}

# Escape a string for safe single-quoted SQL inclusion.
sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

# ── 1. read pending requests (eligible by backoff) ───────────────────────────

log "Worker run start (max_attempts=${MAX_ATTEMPTS}, dry_run=${WORKER_DRY_RUN})"

# Backoff: a row that already failed N attempts waits N*5 minutes before retry.
SELECT_SQL="SELECT id, service_id, user_id, region_id, attempts
  FROM mod_pexnode_region_queue
  WHERE status='pending'
    AND attempts < ${MAX_ATTEMPTS}
    AND updated_at <= DATE_SUB(NOW(), INTERVAL (attempts * 5) MINUTE);"

# whmcs-db.sh prints a tab-separated header row first; skip it.
mapfile -t ROWS < <(db "$SELECT_SQL" 2>/dev/null | tail -n +2 || true)

if [[ "${#ROWS[@]}" -eq 0 ]]; then
  log "No pending provisioning requests. Done."
  exit 0
fi

log "Found ${#ROWS[@]} pending request(s)."

# ── 2. group services by region ──────────────────────────────────────────────

declare -A REGION_SERVICES   # region -> space-separated service ids

for row in "${ROWS[@]}"; do
  [[ -z "$row" ]] && continue
  IFS=$'\t' read -r _ service_id _ region_id _ <<< "$row"
  [[ -z "${service_id:-}" || -z "${region_id:-}" ]] && continue

  if ! [[ "$service_id" =~ ^[0-9]+$ ]]; then
    err "Skipping row with non-numeric service_id: '${service_id}'"
    continue
  fi

  if ! region_is_valid "$region_id"; then
    err "Region '${region_id}' (service ${service_id}) not in regions.conf allowlist — marking failed."
    queue_update "$service_id" "failed" "last_error='region not in allowlist', attempts=attempts+1"
    bash "${SCRIPT_DIR}/notify-ops.sh" \
      "Provisjonering avvist: ukjent region" \
      "Service #${service_id} ba om region '${region_id}' som ikke finnes i regions.conf. Sjekk produktets region-valg." || true
    continue
  fi

  REGION_SERVICES["$region_id"]+="${service_id} "
done

# ── 3. process each region under a per-region lock ───────────────────────────

for region in "${!REGION_SERVICES[@]}"; do
  services="${REGION_SERVICES[$region]}"
  log "Processing region '${region}' for service(s): ${services}"

  region_lock="${LOCK_DIR}/pexnode-region-${region}.lock"
  exec 8>"$region_lock"
  if ! flock -n 8; then
    log "Region '${region}' is already being provisioned by another run — skipping this pass."
    continue
  fi

  node_ready=false

  # 4. Idempotency guard: does a node already exist for this region?
  if grep -q "^${region}	" "${REPO_ROOT}/config/nodes.state" 2>/dev/null; then
    log "Region '${region}' already has a node in nodes.state — skipping VPS creation."
    node_ready=true
  else
    # Mark all waiting services as provisioning.
    for sid in $services; do
      queue_update "$sid" "provisioning" "attempts=attempts+1"
    done

    if [[ "$WORKER_DRY_RUN" == "true" ]]; then
      log "[dry-run] would run: create-cloud-node.sh ${region}"
      node_ready=true
    else
      log "Running create-cloud-node.sh for region '${region}'..."
      if bash "${SCRIPT_DIR}/create-cloud-node.sh" "$region" </dev/null; then
        node_ready=true
        log "Region '${region}' provisioned successfully."
      else
        rc=$?
        err "create-cloud-node.sh failed for region '${region}' (exit ${rc})."
        for sid in $services; do
          attempts_now=$(db "SELECT attempts FROM mod_pexnode_region_queue WHERE service_id=${sid};" 2>/dev/null | tail -n +2 | head -1 | tr -d '[:space:]')
          if [[ "${attempts_now:-0}" =~ ^[0-9]+$ ]] && [[ "$attempts_now" -ge "$MAX_ATTEMPTS" ]]; then
            queue_update "$sid" "failed" "last_error='provisioning failed after ${MAX_ATTEMPTS} attempts'"
            bash "${SCRIPT_DIR}/notify-ops.sh" \
              "Provisjonering feilet: ${region}" \
              "Service #${sid} i region ${region} feilet etter ${MAX_ATTEMPTS} forsøk. Manuell handling kreves: sjekk create-cloud-node.sh-loggen og provider-konsollen." || true
          else
            # Back to pending for retry on a later run (backoff applies).
            queue_update "$sid" "pending" "last_error='provisioning attempt failed, will retry'"
          fi
        done
        flock -u 8
        continue
      fi
    fi
  fi

  # 5. Node is ready — find its Pterodactyl node id and complete each service.
  [[ "$node_ready" == true ]] || continue

  node_id=""
  if [[ -f "${REPO_ROOT}/config/nodes.state" ]]; then
    node_id=$(grep "^${region}	" "${REPO_ROOT}/config/nodes.state" 2>/dev/null | tail -1 | awk -F'\t' '{print $5}')
  fi

  for sid in $services; do
    queue_update "$sid" "node_ready" "${node_id:+node_id=${node_id}}"

    if [[ "$WORKER_DRY_RUN" == "true" ]]; then
      log "[dry-run] would complete service ${sid} via ModuleCreate"
      queue_update "$sid" "completed"
      continue
    fi

    log "Completing service #${sid} via WHMCS ModuleCreate..."
    if bash "$WHMCS_API" call ModuleCreate "serviceid=${sid}" >/dev/null 2>&1 \
       || bash "$WHMCS_API" local ModuleCreate "serviceid=${sid}" >/dev/null 2>&1; then
      queue_update "$sid" "completed"
      log "Service #${sid} completed on region '${region}'."
    else
      queue_update "$sid" "node_ready" "last_error='node ready but ModuleCreate failed; retrying'"
      err "ModuleCreate failed for service #${sid} (node is ready). Will retry next run."
      # Re-open for retry: node exists so next run skips VPS creation and just
      # retries the completion.
      queue_update "$sid" "pending" "last_error='node ready, ModuleCreate pending retry'"
    fi
  done

  flock -u 8
done

log "Worker run complete."
