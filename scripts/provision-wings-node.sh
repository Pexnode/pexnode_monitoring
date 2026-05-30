#!/bin/bash
# Pexnode Wings Node Provisioning Script
# 
# This script prepares a new game server node with:
# - Wings daemon installation
# - Panel integration
# - Netdata monitoring
# - Security hardening (firewall, SSH, kernel parameters)
#
# Usage:
#   ./provision-wings-node.sh <panel_url> <node_id> <api_key> \
#     [<netdata_token>] [<ssh_port>]
#
# Example:
#   ./provision-wings-node.sh https://panel.pexnode.com 1 \
#     ptla_xxxxx your_netdata_token 2222

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
PANEL_URL="${1:-}"
NODE_ID="${2:-}"
WINGS_API_KEY="${3:-}"
NETDATA_TOKEN="${4:-}"
SSH_PORT="${5:-22}"

# Validation
if [[ -z "$PANEL_URL" ]] || [[ -z "$NODE_ID" ]] || [[ -z "$WINGS_API_KEY" ]]; then
  echo "Usage: $0 <panel_url> <node_id> <api_key> [<netdata_token>] [<ssh_port>]"
  echo ""
  echo "Required:"
  echo "  panel_url:     Pterodactyl panel URL (e.g., https://panel.pexnode.com)"
  echo "  node_id:       Node ID in panel (numeric)"
  echo "  api_key:       Application API key from panel (ptla_...)"
  echo ""
  echo "Optional:"
  echo "  netdata_token: Netdata claim token (for monitoring)"
  echo "  ssh_port:      SSH port to use (default: 22)"
  echo ""
  echo "Get API key from:"
  echo "  Panel → Admin → API → Application Keys → Create new"
  exit 1
fi

# Hostname for identification
HOSTNAME=$(hostname)
TIMESTAMP=$(date +%s)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Pexnode Wings Node Provisioning${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Host: $HOSTNAME"
echo "Panel URL: $PANEL_URL"
echo "Node ID: $NODE_ID"
echo "SSH Port: $SSH_PORT"
echo ""

# ============================================================================
# 1. SYSTEM UPDATES
# ============================================================================
echo -e "${BLUE}[1/7] Updating system...${NC}"
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl \
  wget \
  git \
  sudo \
  htop \
  net-tools \
  ufw \
  fail2ban \
  unattended-upgrades \
  apt-listchanges

echo -e "${GREEN}✓ System updated${NC}"

# ============================================================================
# 2. INSTALL DOCKER
# ============================================================================
echo -e "${BLUE}[2/7] Installing Docker...${NC}"

if command -v docker &> /dev/null; then
  echo -e "${YELLOW}⚠ Docker already installed${NC}"
else
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm -f get-docker.sh
  usermod -aG docker root
  echo -e "${GREEN}✓ Docker installed${NC}"
fi

# Enable Docker service
systemctl enable docker
systemctl start docker

# ============================================================================
# 3. INSTALL WINGS
# ============================================================================
echo -e "${BLUE}[3/7] Installing Wings daemon...${NC}"

# Create necessary directories
mkdir -p /etc/pterodactyl
mkdir -p /var/lib/pterodactyl
mkdir -p /var/log/pterodactyl

# Download latest Wings binary
WINGS_VERSION="v1.11.8"  # Update as needed
echo "Downloading Wings $WINGS_VERSION..."

curl -L -o /usr/local/bin/wings \
  "https://github.com/pterodactyl/wings/releases/download/$WINGS_VERSION/wings_linux_amd64"

chmod u+x /usr/local/bin/wings

# Verify installation
if ! /usr/local/bin/wings --version; then
  echo -e "${RED}✗ Wings installation failed${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Wings installed: $(/usr/local/bin/wings --version)${NC}"

# ============================================================================
# 4. CONFIGURE WINGS
# ============================================================================
echo -e "${BLUE}[4/7] Configuring Wings...${NC}"

# Fetch node configuration from panel
CONFIG_URL="${PANEL_URL}/api/application/nodes/${NODE_ID}/configuration"

echo "Fetching configuration from: $CONFIG_URL"

if ! curl -s -H "Authorization: Bearer ${WINGS_API_KEY}" \
  -H "Content-Type: application/json" \
  -X GET "$CONFIG_URL" \
  -o /etc/pterodactyl/config.yml; then
  echo -e "${RED}✗ Failed to fetch node configuration${NC}"
  echo "Check:"
  echo "  - Panel URL is correct"
  echo "  - API key is valid"
  echo "  - Node ID exists in panel"
  exit 1
fi

# Verify config was downloaded
if [ ! -f /etc/pterodactyl/config.yml ]; then
  echo -e "${RED}✗ Configuration file not found${NC}"
  exit 1
fi

# Set proper permissions
chown root:root /etc/pterodactyl/config.yml
chmod 600 /etc/pterodactyl/config.yml

echo -e "${GREEN}✓ Wings configured${NC}"

# ============================================================================
# 5. SETUP WINGS SYSTEMD SERVICE
# ============================================================================
echo -e "${BLUE}[5/7] Installing Wings systemd service...${NC}"

cat > /etc/systemd/system/wings.service << 'EOF'
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

systemctl daemon-reload
systemctl enable wings
systemctl start wings

# Wait for Wings to start
sleep 3

if systemctl is-active --quiet wings; then
  echo -e "${GREEN}✓ Wings service running${NC}"
else
  echo -e "${RED}✗ Wings failed to start${NC}"
  systemctl status wings
  journalctl -u wings -n 50
  exit 1
fi

# ============================================================================
# 6. SETUP NETDATA MONITORING (if token provided)
# ============================================================================
if [[ -n "$NETDATA_TOKEN" ]]; then
  echo -e "${BLUE}[6/7] Setting up Netdata monitoring...${NC}"
  
  # Install Docker (already done above, but ensure)
  if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}⚠ Docker not available for Netdata${NC}"
  else
    # Deploy Netdata child
    docker stop netdata-child 2>/dev/null || true
    docker rm netdata-child 2>/dev/null || true
    
    NETDATA_HOSTNAME="${HOSTNAME}-wings"
    
    docker run -d \
      --name netdata-child \
      --hostname "$NETDATA_HOSTNAME" \
      --network host \
      --cap-add SYS_PTRACE \
      --cap-add SYS_ADMIN \
      --security-opt apparmor=unconfined \
      -e NETDATA_CLAIM_TOKEN="$NETDATA_TOKEN" \
      -e NETDATA_CLAIM_URL="https://app.netdata.cloud" \
      -e NETDATA_CLAIM_ONLY="yes" \
      -e NETDATA_TELEMETRY="no" \
      -e DOCKER_HOST=unix:///var/run/docker.sock \
      -v /etc/os-release:/host/etc/os-release:ro \
      -v /proc:/host/proc:ro \
      -v /sys:/host/sys:ro \
      -v /var/run/docker.sock:/var/run/docker.sock:ro \
      -v /etc/timezone:/etc/timezone:ro \
      netdata/netdata:latest
    
    sleep 3
    
    if docker ps | grep -q netdata-child; then
      echo -e "${GREEN}✓ Netdata monitoring enrolled${NC}"
    else
      echo -e "${RED}✗ Netdata failed to start${NC}"
      docker logs netdata-child 2>/dev/null || true
    fi
  fi
else
  echo -e "${YELLOW}[6/7] Skipping Netdata (no token provided)${NC}"
fi

# ============================================================================
# 7. SECURITY HARDENING
# ============================================================================
echo -e "${BLUE}[7/7] Applying security hardening...${NC}"

# ----
# 7.1: SSH Hardening
# ----
if [[ "$SSH_PORT" != "22" ]]; then
  echo "Configuring SSH port: $SSH_PORT"
  
  # Backup original
  cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.backup.${TIMESTAMP}"
  
  # Update port
  sed -i "s/^#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
  sed -i "s/^Port 22$/Port $SSH_PORT/" /etc/ssh/sshd_config
fi

# Disable password authentication (key-only)
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication yes$/PasswordAuthentication no/' /etc/ssh/sshd_config

# Disable root login (if SSH key is setup)
sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes$/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# Other SSH hardening
cat >> /etc/ssh/sshd_config << 'EOF'

# Pexnode Security Hardening
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
MaxAuthTries 3
MaxSessions 2
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

# Test and restart SSH
if sshd -t; then
  systemctl restart sshd
  echo -e "${GREEN}✓ SSH hardened (port: $SSH_PORT)${NC}"
else
  echo -e "${RED}✗ SSH configuration error${NC}"
  systemctl restart sshd || true
fi

# ----
# 7.2: UFW Firewall
# ----
echo "Configuring UFW firewall..."

# Enable UFW
ufw --force enable

# Default deny inbound
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (on custom port)
ufw allow "$SSH_PORT/tcp" comment "SSH"

# Allow common game server ports (25500-25600 for Wings + game servers)
ufw allow 25500:25600/tcp comment "Game Servers"
ufw allow 25500:25600/udp comment "Game Servers"

# Allow HTTP/HTTPS (if needed for other services)
ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"

# Rate limiting on SSH
ufw limit "$SSH_PORT/tcp" comment "SSH Rate Limit"

# Enable UFW
systemctl enable ufw
systemctl restart ufw

echo -e "${GREEN}✓ Firewall configured${NC}"

# ----
# 7.3: Fail2Ban
# ----
echo "Configuring Fail2Ban..."

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

[sshd-ddos]
enabled = true
port = $SSH_PORT
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo -e "${GREEN}✓ Fail2Ban configured${NC}"

# ----
# 7.4: Kernel Hardening
# ----
echo "Applying kernel hardening..."

cat >> /etc/sysctl.conf << 'EOF'

# Pexnode Security Hardening
# Disable ICMP redirect
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv6.conf.all.send_redirects = 0
net.ipv6.conf.default.send_redirects = 0

# Disable ICMP redirect acceptance
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Enable SYN cookies
net.ipv4.tcp_syncookies = 1

# Ignore ICMP ping (optional - can break monitoring)
# net.ipv4.icmp_echo_ignore_all = 1

# Log suspicious packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Protect against tcp time-wait assassination hazards
net.ipv4.tcp_rfc1337 = 1

# Disable source packet routing
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
EOF

sysctl -p -q

echo -e "${GREEN}✓ Kernel hardening applied${NC}"

# ----
# 7.5: Automatic Security Updates
# ----
echo "Configuring automatic security updates..."

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

systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

echo -e "${GREEN}✓ Automatic updates configured${NC}"

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ Provisioning complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Node Details:"
echo "  Hostname: $HOSTNAME"
echo "  SSH Port: $SSH_PORT"
echo "  Wings: Running (systemctl status wings)"
if [[ -n "$NETDATA_TOKEN" ]]; then
  echo "  Monitoring: Enrolled"
fi
echo ""
echo "Next steps:"
echo "  1. SSH: ssh -p $SSH_PORT root@$(hostname -I | awk '{print $1}')"
echo "  2. Check Wings status: systemctl status wings"
echo "  3. In panel, verify node appears and is online"
echo "  4. Create allocations and start provisioning servers"
echo ""
echo "Security applied:"
echo "  ✓ SSH port changed to $SSH_PORT"
echo "  ✓ Password auth disabled"
echo "  ✓ UFW firewall enabled"
echo "  ✓ Fail2Ban configured"
echo "  ✓ Kernel hardening applied"
echo "  ✓ Automatic updates enabled"
echo ""
