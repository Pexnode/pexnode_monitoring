#!/bin/bash
# Remove Netdata ACI deployment.

set -Eeuo pipefail

: "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID is required}"
: "${AZURE_SP_APP_ID:?AZURE_SP_APP_ID is required}"
: "${AZURE_SP_PASSWORD:?AZURE_SP_PASSWORD is required}"
: "${AZURE_SP_TENANT_ID:?AZURE_SP_TENANT_ID is required}"

RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-pexnode-monitoring}"
CONTAINER_NAME="${AZURE_CONTAINER_NAME:-netdata-parent}"

az login --service-principal \
  --username "$AZURE_SP_APP_ID" \
  --password "$AZURE_SP_PASSWORD" \
  --tenant "$AZURE_SP_TENANT_ID" >/dev/null

az account set --subscription "$AZURE_SUBSCRIPTION_ID"

if az container show --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" >/dev/null 2>&1; then
  az container delete --resource-group "$RESOURCE_GROUP" --name "$CONTAINER_NAME" --yes
  echo "Deleted ${CONTAINER_NAME}"
else
  echo "Container ${CONTAINER_NAME} not found"
fi
