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
    NETDATA_TELEMETRY="no" >/dev/null

FQDN=$(az container show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" --query ipAddress.fqdn -o tsv)
IP=$(az container show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" --query ipAddress.ip -o tsv)

echo "Netdata deployed"
echo "FQDN: ${FQDN}"
echo "IP: ${IP}"
echo "Dashboard: http://${FQDN}:19999"
