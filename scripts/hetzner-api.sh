#!/bin/bash
# Hetzner Cloud API helper
#
# Usage:
#   scripts/hetzner-api.sh test
#   scripts/hetzner-api.sh get   <path>
#   scripts/hetzner-api.sh post  <path> <json_body>
#   scripts/hetzner-api.sh delete <path>
#
#   scripts/hetzner-api.sh locations
#   scripts/hetzner-api.sh server-types [location]
#   scripts/hetzner-api.sh server-get   <server_id>
#   scripts/hetzner-api.sh server-create <name> <location> <server_type> <ssh_key_id> [user_data_file]
#   scripts/hetzner-api.sh server-delete <server_id>
#   scripts/hetzner-api.sh ssh-keys
#
# Required env: HETZNER_API_TOKEN
# Load env:     source scripts/load-env.sh

set -Eeuo pipefail

HETZNER_API_BASE="https://api.hetzner.cloud/v1"

# ── env ─────────────────────────────────────────────────────────────────────

if [[ -z "${HETZNER_API_TOKEN:-}" ]]; then
  # Try loading env from standard locations
  [[ -f "$HOME/.config/pexnode/env" ]] && source "$HOME/.config/pexnode/env"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  [[ -f "$REPO_ROOT/.env.local" ]] && source "$REPO_ROOT/.env.local"
fi

if [[ -z "${HETZNER_API_TOKEN:-}" ]]; then
  echo "ERROR: HETZNER_API_TOKEN is not set." >&2
  echo "Get one at: console.hetzner.cloud -> Project -> Security -> API Tokens" >&2
  exit 1
fi

# ── curl wrapper ─────────────────────────────────────────────────────────────

_hetzner_curl() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  local args=(
    -s -f
    -X "$method"
    -H "Authorization: Bearer ${HETZNER_API_TOKEN}"
    -H "Content-Type: application/json"
  )

  if [[ -n "$body" ]]; then
    args+=( -d "$body" )
  fi

  local response
  local http_code
  response=$(curl "${args[@]}" -w '\n__HTTP_CODE__%{http_code}' "${HETZNER_API_BASE}${path}" 2>&1)
  http_code=$(echo "$response" | grep '__HTTP_CODE__' | sed 's/.*__HTTP_CODE__//')
  response=$(echo "$response" | grep -v '__HTTP_CODE__')

  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: Hetzner API returned HTTP ${http_code}" >&2
    echo "$response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('error',{}).get('message','unknown error'))" 2>/dev/null >&2 || echo "$response" >&2
    return 1
  fi

  echo "$response"
}

# ── commands ─────────────────────────────────────────────────────────────────

CMD="${1:-help}"

case "$CMD" in

  test)
    echo "Testing Hetzner API authentication..."
    result=$(_hetzner_curl GET /datacenters)
    count=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('datacenters',[])))")
    echo "OK — authenticated. ${count} datacenters visible."
    ;;

  locations)
    _hetzner_curl GET /locations | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f\"{'Name':<8} {'City':<20} {'Country':<8} {'Network Zone'}\")
print('-' * 50)
for l in sorted(data['locations'], key=lambda x: x['network_zone']):
    print(f\"{l['name']:<8} {l['city']:<20} {l['country']:<8} {l['network_zone']}\")
"
    ;;

  server-types)
    location_filter="${2:-}"
    path="/server_types"
    [[ -n "$location_filter" ]] && path+="?location=${location_filter}"
    _hetzner_curl GET "$path" | python3 -c "
import json, sys
data = json.load(sys.stdin)
types = data['server_types']
# Filter to dedicated (CCX) and show key info
print(f\"{'Name':<10} {'CPU':<6} {'RAM':<8} {'Disk':<8} {'Architecture'}\")
print('-' * 50)
for t in sorted(types, key=lambda x: x['memory']):
    if t.get('cpu_type') == 'dedicated':
        print(f\"{t['name']:<10} {t['cores']:<6} {str(t['memory'])+'GB':<8} {str(t['disk'])+'GB':<8} {t.get('architecture','')}\")
"
    ;;

  server-get)
    server_id="${2:?Usage: hetzner-api.sh server-get <server_id>}"
    _hetzner_curl GET "/servers/${server_id}" | python3 -c "
import json, sys
s = json.load(sys.stdin)['server']
print(f\"ID:       {s['id']}\")
print(f\"Name:     {s['name']}\")
print(f\"Status:   {s['status']}\")
print(f\"IPv4:     {s['public_net']['ipv4']['ip']}\")
print(f\"Location: {s['datacenter']['location']['name']}\")
print(f\"Type:     {s['server_type']['name']}\")
"
    ;;

  server-create)
    name="${2:?Usage: hetzner-api.sh server-create <name> <location> <server_type> <ssh_key_id> [user_data_file]}"
    location="${3:?missing location}"
    server_type="${4:?missing server_type}"
    ssh_key_id="${5:?missing ssh_key_id}"
    user_data_file="${6:-}"

    user_data_json="null"
    if [[ -n "$user_data_file" && -f "$user_data_file" ]]; then
      user_data_json=$(python3 -c "import json,sys; print(json.dumps(open(sys.argv[1]).read()))" "$user_data_file")
    fi

    body=$(python3 -c "
import json, sys
obj = {
    'name': sys.argv[1],
    'location': sys.argv[2],
    'server_type': sys.argv[3],
    'image': 'ubuntu-24.04',
    'ssh_keys': [sys.argv[4]],
    'user_data': json.loads(sys.argv[5]) if sys.argv[5] != 'null' else None,
    'start_after_create': True,
    'labels': {'managed-by': 'pexnode', 'role': 'wings'}
}
# Remove None values
obj = {k: v for k, v in obj.items() if v is not None}
print(json.dumps(obj))
" "$name" "$location" "$server_type" "$ssh_key_id" "$user_data_json")

    echo "Creating Hetzner server: name=${name} location=${location} type=${server_type}"
    result=$(_hetzner_curl POST /servers "$body")
    server_id=$(echo "$result" | python3 -c "import json,sys; print(json.load(sys.stdin)['server']['id'])")
    echo "Created server ID: ${server_id}"
    echo "$result"
    ;;

  server-delete)
    server_id="${2:?Usage: hetzner-api.sh server-delete <server_id>}"
    echo "Deleting Hetzner server ${server_id}..."
    _hetzner_curl DELETE "/servers/${server_id}"
    echo "Deleted."
    ;;

  ssh-keys)
    _hetzner_curl GET /ssh_keys | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f\"{'ID':<12} {'Name'}\")
print('-' * 40)
for k in data['ssh_keys']:
    print(f\"{k['id']:<12} {k['name']}\")
"
    ;;

  get)
    path="${2:?Usage: hetzner-api.sh get <path>}"
    _hetzner_curl GET "$path"
    ;;

  post)
    path="${2:?Usage: hetzner-api.sh post <path> <json_body>}"
    body="${3:?missing json_body}"
    _hetzner_curl POST "$path" "$body"
    ;;

  delete)
    path="${2:?Usage: hetzner-api.sh delete <path>}"
    _hetzner_curl DELETE "$path"
    ;;

  help|*)
    cat <<'HELP'
Hetzner Cloud API helper

Commands:
  test                                        Verify authentication
  locations                                   List all locations
  server-types [location]                     List dedicated server types
  server-get   <server_id>                    Get server status and IP
  server-create <name> <loc> <type> <ssh_key_id> [user_data_file]
  server-delete <server_id>
  ssh-keys                                    List SSH keys in project
  get    <path>                               Raw GET request
  post   <path> <json_body>                   Raw POST request
  delete <path>                               Raw DELETE request

Required env: HETZNER_API_TOKEN
HELP
    ;;
esac
