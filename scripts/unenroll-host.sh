#!/bin/bash
# Remove a host from monitoring
# Usage: ./unenroll-host.sh <host_ip>

HOST_IP="${1:-}"

if [[ -z "$HOST_IP" ]]; then
  echo "Usage: $0 <host_ip>"
  exit 1
fi

echo "Removing $HOST_IP from monitoring..."

ssh root@"$HOST_IP" bash << 'EOF'
docker stop netdata-child 2>/dev/null || true
docker rm netdata-child 2>/dev/null || true
systemctl disable pexnode-netdata-child.service 2>/dev/null || true
systemctl stop pexnode-netdata-child.service 2>/dev/null || true
rm -f /opt/pexnode-monitoring/enroll-child.sh
echo "✅ Netdata child removed"
EOF

echo "✅ Host unenrolled"
