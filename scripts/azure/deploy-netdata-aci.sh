#!/bin/bash
# Deploy/update Netdata parent as low-cost Azure Container Instance.
# Designed to run non-interactively with service principal env vars.

set -Eeuo pipefail

: "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID is required}"
: "${AZURE_SP_APP_ID:?AZURE_SP_APP_ID is required}"
: "${AZURE_SP_PASSWORD:?AZURE_SP_PASSWORD is required}"
: "${AZURE_SP_TENANT_ID:?AZURE_SP_TENANT_ID is required}"
: "${NETDATA_CLAIM_TOKEN:?NETDATA_CLAIM_TOKEN is required}"

RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-pexnode-monitoring}"
LOCATION="${AZURE_LOCATION:-westeurope}"
CONTAINER_NAME="${AZURE_CONTAINER_NAME:-netdata-parent}"
DNS_LABEL="${AZURE_DNS_LABEL:-pexnode-netdata}"
CPU="${AZURE_ACI_CPU:-0.5}"
MEMORY="${AZURE_ACI_MEMORY_GB:-1.0}"

az login --service-principal \
  --username "$AZURE_SP_APP_ID" \
  --password "$AZURE_SP_PASSWORD" \
  --tenant "$AZURE_SP_TENANT_ID" >/dev/null

az account set --subscription "$AZURE_SUBSCRIPTION_ID"

if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" >/dev/null
fi

if az container show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" >/dev/null 2>&1; then
  az container delete --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" --yes >/dev/null
fi

az container create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CONTAINER_NAME" \
  --image netdata/netdata:latest \
  --os-type Linux \
  --cpu "$CPU" \
  --memory "$MEMORY" \
  --ports 19999 \
  --dns-name-label "$DNS_LABEL" \
  --restart-policy Always \
  --environment-variables \
    NETDATA_CLAIM_TOKEN="$NETDATA_CLAIM_TOKEN" \
    NETDATA_CLAIM_URL="https://app.netdata.cloud" \
    NETDATA_CLAIM_ONLY="no" \
    NETDATA_TELEMETRY="no" \
    DISCORD_WEBHOOK_OPS="${DISCORD_WEBHOOK_OPS:-}" \
    NETDATA_STREAMING_API_KEY="${NETDATA_STREAMING_API_KEY:-449c2b8f-8a52-467c-b6e6-2532dfafadc2}" \
  --command-line 'sh -c "if [ -n \"$DISCORD_WEBHOOK_OPS\" ]; then printf \"SEND_DISCORD=YES\nDISCORD_WEBHOOK_URL=%s\nDEFAULT_RECIPIENT_DISCORD=sysadmin\nrole_recipients_discord[sysadmin]=%s\nSEND_EMAIL=NO\nSEND_SLACK=NO\nSEND_TELEGRAM=NO\n\" \"$DISCORD_WEBHOOK_OPS\" \"$DISCORD_WEBHOOK_OPS\" > /etc/netdata/health_alarm_notify.conf; fi && printf \"[%s]\n    enabled = yes\n    default memory = save\n    health enabled by default = auto\n    allow from = *\n    default history = 3600\n    default update every = 1\n\" \"$NETDATA_STREAMING_API_KEY\" > /etc/netdata/stream.conf && mkdir -p /etc/netdata/go.d && printf \"jobs:\\n  - name: panel\\n    url: https://panel.pexnode.com\\n    status_accepted:\\n      - 200\\n      - 302\\n      - 401\\n  - name: billing\\n    url: https://billing.pexnode.com\\n    status_accepted:\\n      - 200\\n      - 302\\n\" > /etc/netdata/go.d/httpcheck.conf && exec /usr/sbin/netdata -D -u netdata -s / -p 19999 0</dev/null"' \
  >/dev/null

FQDN=$(az container show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" --query ipAddress.fqdn -o tsv)
IP=$(az container show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" --query ipAddress.ip -o tsv)

echo "Netdata deployed"
echo "FQDN: ${FQDN}"
echo "IP: ${IP}"
echo "Dashboard: http://${FQDN}:19999"
