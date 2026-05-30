#!/bin/bash
# One-time helper to create least-scope Azure access for monitoring automation.
# Run manually from an operator machine already logged into Azure.

set -Eeuo pipefail

SUBSCRIPTION_ID="${1:-}"
RESOURCE_GROUP="${2:-pexnode-monitoring}"
SP_NAME="${3:-pexnode-monitoring-ops}"

if [[ -z "$SUBSCRIPTION_ID" ]]; then
  echo "Usage: $0 <subscription_id> [resource_group] [sp_name]"
  exit 1
fi

az account set --subscription "$SUBSCRIPTION_ID"

if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
  az group create --name "$RESOURCE_GROUP" --location westeurope >/dev/null
fi

SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

az ad sp create-for-rbac \
  --name "$SP_NAME" \
  --role Contributor \
  --scopes "$SCOPE" \
  --sdk-auth
