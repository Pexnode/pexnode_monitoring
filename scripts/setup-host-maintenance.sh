#!/bin/bash
# Install recurring host maintenance checks for a Wings node.
# Safe to run multiple times.

set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root"
  exit 1
fi

mkdir -p /usr/local/sbin

cat > /usr/local/sbin/pexnode-maintenance-check.sh << 'EOF'
#!/bin/bash
set -Eeuo pipefail

log() {
  logger -t pexnode-maintenance "$*"
}

if systemctl list-unit-files | grep -q '^wings\.service'; then
  if ! systemctl is-active --quiet wings; then
    systemctl restart wings || true
    log "wings service restarted by maintenance check"
  fi
fi

if command -v docker >/dev/null 2>&1; then
  if docker ps -a --format '{{.Names}}' | grep -qx 'netdata-child'; then
    if ! docker ps --format '{{.Names}}' | grep -qx 'netdata-child'; then
      docker start netdata-child >/dev/null 2>&1 || true
      log "netdata-child restarted by maintenance check"
    fi
  fi
fi
EOF

chmod 755 /usr/local/sbin/pexnode-maintenance-check.sh

cat > /etc/cron.d/pexnode-host-maintenance << 'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Every 5 minutes: ensure key services are still healthy
*/5 * * * * root /usr/local/sbin/pexnode-maintenance-check.sh

# Daily: small docker cleanup of dangling artifacts
17 3 * * * root /usr/bin/docker system prune -f --volumes >/var/log/pexnode-docker-prune.log 2>&1 || true
EOF

chmod 644 /etc/cron.d/pexnode-host-maintenance

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true
fi

echo "Host maintenance jobs installed"
