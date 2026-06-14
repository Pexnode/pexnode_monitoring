#!/bin/bash
# Vultr API helper
#
# Usage:
#   scripts/vultr-api.sh test
#   scripts/vultr-api.sh get    <path>
#   scripts/vultr-api.sh post   <path> <json_body>
#   scripts/vultr-api.sh delete <path>
#
#   scripts/vultr-api.sh regions
#   scripts/vultr-api.sh plans [region]
#   scripts/vultr-api.sh instance-get    <instance_id>
#   scripts/vultr-api.sh instance-create <label> <region> <plan> <ssh_key_id> [user_data_file]
#   scripts/vultr-api.sh instance-delete <instance_id>
#   scripts/vultr-api.sh ssh-keys
#
# Required env: VULTR_API_TOKEN
# Load env:     source scripts/load-env.sh

# shellcheck disable=SC1091  # env files are runtime-only and not tracked in the repo
set -Eeuo pipefail

VULTR_API_BASE="https://api.vultr.com/v2"

# ── env ─────────────────────────────────────────────────────────────────────

if [[ -z "${VULTR_API_TOKEN:-}" ]]; then
  [[ -f "$HOME/.config/pexnode/env" ]] && source "$HOME/.config/pexnode/env"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  [[ -f "$REPO_ROOT/.env.local" ]] && source "$REPO_ROOT/.env.local"
fi

if [[ -z "${VULTR_API_TOKEN:-}" ]]; then
  echo "ERROR: VULTR_API_TOKEN is not set." >&2
  echo "Get one at: my.vultr.com/settings/#settingsapi" >&2
  exit 1
fi

# ── curl wrapper ─────────────────────────────────────────────────────────────

_vultr_curl() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  local args=(
    -s
    -X "$method"
    -H "Authorization: Bearer ${VULTR_API_TOKEN}"
    -H "Content-Type: application/json"
  )

  if [[ -n "$body" ]]; then
    args+=( -d "$body" )
  fi

  local response http_code
  response=$(curl "${args[@]}" -w '\n__HTTP_CODE__%{http_code}' "${VULTR_API_BASE}${path}" 2>&1)
  http_code=$(echo "$response" | grep '__HTTP_CODE__' | sed 's/.*__HTTP_CODE__//')
  response=$(echo "$response" | grep -v '__HTTP_CODE__')

  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: Vultr API returned HTTP ${http_code}" >&2
    echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error','unknown error'))" 2>/dev/null >&2 || echo "$response" >&2
    return 1
  fi

  echo "$response"
}

# ── commands ─────────────────────────────────────────────────────────────────

CMD="${1:-help}"

case "$CMD" in

  test)
    echo "Testing Vultr API authentication..."
    result=$(_vultr_curl GET /account)
    name=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['account']['name'])")
    echo "OK — authenticated as: ${name}"
    ;;

  regions)
    # Public endpoint — no auth needed, but included here for convenience
    curl -s "${VULTR_API_BASE}/regions" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f\"{'ID':<8} {'City':<22} {'Country':<8} {'Continent'}\")
print('-' * 55)
for r in sorted(data['regions'], key=lambda x: (x['continent'], x['country'])):
    print(f\"{r['id']:<8} {r['city']:<22} {r['country']:<8} {r['continent']}\")
"
    ;;

  plans)
    region_filter="${2:-}"
    path="/plans?type=vc2&per_page=100"
    [[ -n "$region_filter" ]] && path+="&region=${region_filter}"
    _vultr_curl GET "$path" | python3 -c "
import json, sys
data = json.load(sys.stdin)
plans = data.get('plans', [])
# Filter to plans with 4+ vCPU (suitable for Wings)
print(f\"{'ID':<22} {'vCPU':<6} {'RAM':<8} {'Disk':<8} {'Bandwidth'}\")
print('-' * 60)
for p in sorted(plans, key=lambda x: x['ram']):
    if p['vcpu_count'] >= 4:
        print(f\"{p['id']:<22} {p['vcpu_count']:<6} {str(p['ram'])+'MB':<8} {str(p['disk'])+'GB':<8} {str(p.get('bandwidth',0))+'GB'}\")
" 2>/dev/null || _vultr_curl GET "$path"
    ;;

  instance-get)
    instance_id="${2:?Usage: vultr-api.sh instance-get <instance_id>}"
    _vultr_curl GET "/instances/${instance_id}" | python3 -c "
import json, sys
i = json.load(sys.stdin)['instance']
print(f\"ID:       {i['id']}\")
print(f\"Label:    {i['label']}\")
print(f\"Status:   {i['status']} / power: {i['power_status']}\")
print(f\"IPv4:     {i['main_ip']}\")
print(f\"Region:   {i['region']}\")
print(f\"Plan:     {i['plan']}\")
"
    ;;

  instance-create)
    label="${2:?Usage: vultr-api.sh instance-create <label> <region> <plan> <ssh_key_id> [user_data_file]}"
    region="${3:?missing region}"
    plan="${4:?missing plan}"
    ssh_key_id="${5:?missing ssh_key_id}"
    user_data_file="${6:-}"

    user_data_b64=""
    if [[ -n "$user_data_file" && -f "$user_data_file" ]]; then
      user_data_b64=$(base64 -w 0 "$user_data_file")
    fi

    body=$(python3 -c "
import json, sys, base64
obj = {
    'label': sys.argv[1],
    'region': sys.argv[2],
    'plan': sys.argv[3],
    'os_id': 2284,          # Ubuntu 24.04 LTS x64
    'sshkey_id': [sys.argv[4]],
    'backups': 'disabled',
    'enable_ipv6': False,
    'tags': ['pexnode', 'wings'],
}
ud = sys.argv[5]
if ud:
    obj['user_data'] = ud   # already base64-encoded
print(json.dumps(obj))
" "$label" "$region" "$plan" "$ssh_key_id" "$user_data_b64")

    echo "Creating Vultr instance: label=${label} region=${region} plan=${plan}"
    result=$(_vultr_curl POST /instances "$body")
    instance_id=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['instance']['id'])")
    echo "Created instance ID: ${instance_id}"
    echo "$result"
    ;;

  instance-delete)
    instance_id="${2:?Usage: vultr-api.sh instance-delete <instance_id>}"
    echo "Deleting Vultr instance ${instance_id}..."
    _vultr_curl DELETE "/instances/${instance_id}"
    echo "Deleted."
    ;;

  ssh-keys)
    _vultr_curl GET /ssh-keys | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f\"{'ID':<40} {'Name'}\")
print('-' * 60)
for k in data.get('ssh_keys', []):
    print(f\"{k['id']:<40} {k['name']}\")
"
    ;;

  get)
    path="${2:?Usage: vultr-api.sh get <path>}"
    _vultr_curl GET "$path"
    ;;

  post)
    path="${2:?Usage: vultr-api.sh post <path> <json_body>}"
    body="${3:?missing json_body}"
    _vultr_curl POST "$path" "$body"
    ;;

  delete)
    path="${2:?Usage: vultr-api.sh delete <path>}"
    _vultr_curl DELETE "$path"
    ;;

  help|*)
    cat <<'HELP'
Vultr API helper

Commands:
  test                                         Verify authentication
  regions                                      List all regions
  plans [region]                               List 4+ vCPU plans
  instance-get    <instance_id>                Get instance status and IP
  instance-create <label> <region> <plan> <ssh_key_id> [user_data_file]
  instance-delete <instance_id>
  ssh-keys                                     List SSH keys in account
  get    <path>                                Raw GET request
  post   <path> <json_body>                    Raw POST request
  delete <path>                                Raw DELETE request

Required env: VULTR_API_TOKEN
HELP
    ;;
esac
