#!/bin/bash
# Pexnode Wings Node Provisioning Script
#
# Idempotent provisioning for a Wings host:
# - Installs Docker and Wings
# - Pulls node config from panel
# - Ensures systemd services
# - Enrolls Netdata child (optional)
# - Applies security hardening safely
#
# Usage:
#   ./provision-wings-node.sh <panel_url> <node_id> <api_key> [<netdata_token>] [<ssh_port>]

set -Eeuo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PANEL_URL="${1:-}"
NODE_ID="${2:-}"
WINGS_API_KEY="${3:-}"
NETDATA_TOKEN="${4:-}"
SSH_PORT="${5:-22}"
WINGS_VERSION="${WINGS_VERSION:-v1.11.8}"
NETDATA_IMAGE="${NETDATA_IMAGE:-netdata/netdata:latest}"

on_error() {
  local exit_code=$?
  local line_no=$1
  echo -e "${RED}ERROR:${NC} provision-wings-node.sh failed at line ${line_no} (exit ${exit_code})"
  echo "Check logs with: journalctl -u wings -n 100 --no-pager"
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

ensure_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root"
    exit 1
  fi
}

ensure_line() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -Eq "^${key}[[:space:]]+" "$file"; then
    sed -i "s|^${key}[[:space:]].*|${key} ${value}|" "$file"
  else
    echo "${key} ${value}" >> "$file"
  fi
}

ensure_sshd_option() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "$file"; then
    sed -i "s|^[#[:space:]]*${key}[[:space:]].*|${key} ${value}|" "$file"
  else
    echo "${key} ${value}" >> "$file"
  fi
}

if [[ -z "$PANEL_URL" ]] || [[ -z "$NODE_ID" ]] || [[ -z "$WINGS_API_KEY" ]]; then
  echo "Usage: $0 <panel_url> <node_id> <api_key> [<netdata_token>] [<ssh_port>]"
  exit 1
fi

ensure_root

HOSTNAME=$(hostname)
TIMESTAMP=$(date +%s)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Pexnode Wings Node Provisioning${NC}"
echo -e "${BLUE}========================================${NC}"
echo "Host: $HOSTNAME"
echo "Panel URL: $PANEL_URL"
echo "Node ID: $NODE_ID"
echo "SSH Port: $SSH_PORT"
echo

echo -e "${BLUE}[1/7] Ensuring base packages...${NC}"
apt-get update -qq
apt-get install -y -qq \
  curl wget git sudo htop net-tools ufw fail2ban unattended-upgrades apt-listchanges ca-certificates

echo -e "${GREEN}OK: base packages present${NC}"

echo -e "${BLUE}[2/7] Ensuring Docker...${NC}"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  rm -f /tmp/get-docker.sh
fi
systemctl enable docker >/dev/null 2>&1 || true
systemctl start docker

docker info >/dev/null 2>&1

echo -e "${GREEN}OK: Docker ready${NC}"

echo -e "${BLUE}[3/7] Ensuring Wings binary...${NC}"
mkdir -p /etc/pterodactyl /var/lib/pterodactyl /var/log/pterodactyl

current_wings_version=""
if [[ -x /usr/local/bin/wings ]]; then
  current_wings_version=$(/usr/local/bin/wings --version 2>/dev/null || true)
fi

if [[ "$current_wings_version" != *"$WINGS_VERSION"* ]]; then
  curl -fsSL -o /usr/local/bin/wings \
    "https://github.com/pterodactyl/wings/releases/download/${WINGS_VERSION}/wings_linux_amd64"
  chmod u+x /usr/local/bin/wings
fi

/usr/local/bin/wings --version >/dev/null

echo -e "${GREEN}OK: Wings installed${NC}"

echo -e "${BLUE}[4/7] Ensuring Wings config and service...${NC}"
CONFIG_URL="${PANEL_URL}/api/application/nodes/${NODE_ID}/configuration"
TMP_CONFIG="/tmp/pexnode-wings-config-${TIMESTAMP}.yml"

curl -fsSL --retry 3 --retry-delay 2 \
  -H "Authorization: Bearer ${WINGS_API_KEY}" \
  -H "Accept: application/json" \
  -X GET "$CONFIG_URL" \
  -o "$TMP_CONFIG"

if [[ ! -s "$TMP_CONFIG" ]]; then
  echo "Downloaded config is empty"
  exit 1
fi

if [[ ! -f /etc/pterodactyl/config.yml ]] || ! cmp -s "$TMP_CONFIG" /etc/pterodactyl/config.yml; then
  install -m 600 -o root -g root "$TMP_CONFIG" /etc/pterodactyl/config.yml
  wings_config_changed="yes"
else
  wings_config_changed="no"
fi
rm -f "$TMP_CONFIG"

TMP_SERVICE="/tmp/wings.service.${TIMESTAMP}"
cat > "$TMP_SERVICE" << 'EOF'
[Unit]
Description=Pterodactyl Wings Daemon
After=network-online.target
Wants=network-online.target

[Service]
User=root
WorkingDirectory=/var/lib/pterodactyl
LimitNOFILE=4096
LimitNPROC=unlimited
LimitMEMLOCK=unlimited
Type=simple
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
ExecStart=/usr/local/bin/wings

[Install]
WantedBy=multi-user.target
EOF

if [[ ! -f /etc/systemd/system/wings.service ]] || ! cmp -s "$TMP_SERVICE" /etc/systemd/system/wings.service; then
  install -m 644 -o root -g root "$TMP_SERVICE" /etc/systemd/system/wings.service
  wings_service_changed="yes"
else
  wings_service_changed="no"
fi
rm -f "$TMP_SERVICE"

if [[ "$wings_service_changed" == "yes" ]]; then
  systemctl daemon-reload
fi

systemctl enable wings >/dev/null 2>&1 || true
if [[ "$wings_config_changed" == "yes" || "$wings_service_changed" == "yes" ]]; then
  systemctl restart wings
else
  if ! systemctl is-active --quiet wings; then
    systemctl start wings
  fi
fi

if ! systemctl is-active --quiet wings; then
  echo "Wings service is not active"
  systemctl status wings --no-pager || true
  exit 1
fi

echo -e "${GREEN}OK: Wings running${NC}"

if [[ -n "$NETDATA_TOKEN" ]]; then
  echo -e "${BLUE}[5/7] Ensuring Netdata child enrollment...${NC}"

  if docker ps --format '{{.Names}}' | grep -qx 'netdata-child'; then
    echo -e "${YELLOW}SKIP: netdata-child already running${NC}"
  elif docker ps -a --format '{{.Names}}' | grep -qx 'netdata-child'; then
    docker start netdata-child >/dev/null
    echo -e "${GREEN}OK: started existing netdata-child${NC}"
  else
    docker pull "$NETDATA_IMAGE" >/dev/null 2>&1 || true

    docker_args=(
      run -d
      --name netdata-child
      --hostname "${HOSTNAME}-wings"
      --network host
      --cap-add SYS_PTRACE
      --cap-add SYS_ADMIN
      --security-opt apparmor=unconfined
      -e NETDATA_CLAIM_TOKEN="$NETDATA_TOKEN"
      -e NETDATA_CLAIM_URL="https://app.netdata.cloud"
      -e NETDATA_CLAIM_ONLY=yes
      -e NETDATA_TELEMETRY=no
      -e DOCKER_HOST=unix:///var/run/docker.sock
      -v /etc/os-release:/host/etc/os-release:ro
      -v /proc:/host/proc:ro
      -v /sys:/host/sys:ro
      -v /var/run/docker.sock:/var/run/docker.sock:ro
    )

    if [[ -f /etc/timezone ]]; then
      docker_args+=( -v /etc/timezone:/etc/timezone:ro )
    elif [[ -f /etc/localtime ]]; then
      docker_args+=( -v /etc/localtime:/etc/localtime:ro )
    fi

    docker_args+=( "$NETDATA_IMAGE" )
    docker "${docker_args[@]}"

    if ! docker ps --format '{{.Names}}' | grep -qx 'netdata-child'; then
      echo "netdata-child did not come up"
      docker logs --tail 80 netdata-child || true
      exit 1
    fi

    echo -e "${GREEN}OK: Netdata enrolled${NC}"
  fi
else
  echo -e "${YELLOW}[5/7] Skipping Netdata (no token provided)${NC}"
fi

echo -e "${BLUE}[6/7] Applying SSH and firewall hardening...${NC}"
cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.backup.${TIMESTAMP}"

ensure_sshd_option /etc/ssh/sshd_config Port "$SSH_PORT"
ensure_sshd_option /etc/ssh/sshd_config PasswordAuthentication no
ensure_sshd_option /etc/ssh/sshd_config PermitRootLogin prohibit-password
ensure_sshd_option /etc/ssh/sshd_config X11Forwarding no
ensure_sshd_option /etc/ssh/sshd_config PrintMotd no
ensure_sshd_option /etc/ssh/sshd_config MaxAuthTries 3
ensure_sshd_option /etc/ssh/sshd_config MaxSessions 2
ensure_sshd_option /etc/ssh/sshd_config LoginGraceTime 30
ensure_sshd_option /etc/ssh/sshd_config ClientAliveInterval 300
ensure_sshd_option /etc/ssh/sshd_config ClientAliveCountMax 2

if sshd -t; then
  systemctl restart sshd
else
  cp "/etc/ssh/sshd_config.backup.${TIMESTAMP}" /etc/ssh/sshd_config
  systemctl restart sshd || true
  echo "Invalid sshd config generated, restored backup"
  exit 1
fi

ufw --force enable >/dev/null 2>&1 || true
ufw default deny incoming
ufw default allow outgoing

ufw allow "${SSH_PORT}/tcp" comment "SSH" >/dev/null 2>&1 || true
ufw allow 25500:25600/tcp comment "Game Servers" >/dev/null 2>&1 || true
ufw allow 25500:25600/udp comment "Game Servers" >/dev/null 2>&1 || true
ufw allow 80/tcp comment "HTTP" >/dev/null 2>&1 || true
ufw allow 443/tcp comment "HTTPS" >/dev/null 2>&1 || true
ufw limit "${SSH_PORT}/tcp" comment "SSH Rate Limit" >/dev/null 2>&1 || true

systemctl enable ufw >/dev/null 2>&1 || true
systemctl restart ufw

echo -e "${GREEN}OK: SSH and firewall hardened${NC}"

echo -e "${BLUE}[7/7] Applying fail2ban, sysctl, and updates...${NC}"
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = $SSH_PORT
maxretry = 3
bantime = 7200
EOF

systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban

cat > /etc/sysctl.d/99-pexnode-hardening.conf << 'EOF'
# Pexnode Security Hardening
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.send_redirects = 0
net.ipv6.conf.default.send_redirects = 0

net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

net.ipv4.tcp_syncookies = 1

net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

net.ipv4.tcp_rfc1337 = 1

net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
EOF

sysctl --system >/dev/null

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF

systemctl enable unattended-upgrades >/dev/null 2>&1 || true
systemctl restart unattended-upgrades

echo -e "${GREEN}OK: system hardening complete${NC}"

echo
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Provisioning complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo "Hostname: $HOSTNAME"
echo "SSH Port: $SSH_PORT"
echo "Wings: $(systemctl is-active wings)"
if [[ -n "$NETDATA_TOKEN" ]]; then
  echo "Monitoring: enrolled"
fi
