#!/bin/bash
# Cloud-Init Bootstrap for Wings Provisioning
# 
# Usage:
# Include this as user-data in cloud provider (Azure, AWS, etc.)
#
# Example for Azure:
# az vm create --resource-group rg --name game-node-1 \
#   --image UbuntuLTS \
#   --custom-data provision-wings-bootstrap.sh \
#   --admin-username root
#
# Or paste content into:
#   Azure Portal → Create VM → Advanced → User data field

#!/bin/bash
set -e

# CONFIGURATION (edit these or pass as env vars)
export PANEL_URL="${PANEL_URL:-https://panel.pexnode.com}"
export NODE_ID="${NODE_ID:-}"
export WINGS_API_KEY="${WINGS_API_KEY:-}"
export NETDATA_TOKEN="${NETDATA_TOKEN:-}"
export SSH_PORT="${SSH_PORT:-22}"

# Log all output
exec > >(tee -a /var/log/pexnode-provision.log)
exec 2>&1

echo "=========================================="
echo "Pexnode Wings Provisioning Started"
echo "=========================================="
echo "Time: $(date)"
echo "Host: $(hostname)"
echo ""

# Download and execute provisioning script
PROVISION_URL="https://raw.githubusercontent.com/your-org/pexnode_monitoring/main/scripts/provision-wings-node.sh"

curl -fsSL "$PROVISION_URL" -o /tmp/provision-wings-node.sh
chmod +x /tmp/provision-wings-node.sh

# Run provisioning
/tmp/provision-wings-node.sh \
  "$PANEL_URL" \
  "$NODE_ID" \
  "$WINGS_API_KEY" \
  "$NETDATA_TOKEN" \
  "$SSH_PORT"

# Cleanup
rm -f /tmp/provision-wings-node.sh

echo "=========================================="
echo "Provisioning Completed"
echo "=========================================="
echo "Log: /var/log/pexnode-provision.log"
