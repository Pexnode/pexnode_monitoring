# Azure Netdata Automation

This guide prepares Netdata deployment so the only manual dependency is service principal creation.

## Cost-first baseline

Use Azure Container Instances with:
- CPU: `0.5`
- Memory: `1.0 GB`
- Region: `westeurope` (change if needed)

This is the lowest practical always-on baseline for Netdata parent while keeping enough headroom.

## Prerequisites

Environment variables:

- `AZURE_SUBSCRIPTION_ID`
- `AZURE_SP_APP_ID`
- `AZURE_SP_PASSWORD`
- `AZURE_SP_TENANT_ID`
- `NETDATA_CLAIM_TOKEN`

Optional:
- `AZURE_RESOURCE_GROUP` (default `pexnode-monitoring`)
- `AZURE_CONTAINER_NAME` (default `netdata-parent`)
- `AZURE_LOCATION` (default `westeurope`)
- `AZURE_DNS_LABEL` (default `pexnode-netdata`)
- `AZURE_ACI_CPU` (default `0.5`)
- `AZURE_ACI_MEMORY_GB` (default `1.0`)

## One-time bootstrap

```bash
./scripts/azure/bootstrap-service-principal.sh <subscription_id> pexnode-monitoring pexnode-monitoring-ops
```

## Deploy

```bash
./scripts/azure/deploy-netdata-aci.sh
```

Outputs:
- FQDN
- IP
- Dashboard URL

## Destroy

```bash
./scripts/azure/destroy-netdata-aci.sh
```

## Notes

- ACI uses ephemeral container root filesystem.
- Netdata Cloud claim keeps node identity and dashboard access convenient.
- If you need persistent custom configs, add Azure File Share mount in a later iteration.
