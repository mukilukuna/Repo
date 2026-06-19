# Naming Conventions – Azure Monitoring Baseline

All resources follow the [Microsoft Cloud Adoption Framework (CAF) naming conventions](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming).
Region codes: `weu` = West Europe, `neu` = North Europe.

## Resource naming patterns

| Resource type | Pattern | Example |
|---|---|---|
| Resource group (monitoring) | `rg-<klantcode>-platform-<regio>` | `rg-pilot-platform-weu` |
| Resource group (mock/workload) | `rg-<klantcode>-mock-<regio>` | `rg-pilot-mock-weu` |
| Log Analytics Workspace | `log-<klantcode>-platform-<regio>` | `log-pilot-platform-weu` |
| Action Group (P1) | `ag-monitoring-p1-<regio>` | `ag-monitoring-p1-weu` |
| Action Group (P2) | `ag-monitoring-p2-<regio>` | `ag-monitoring-p2-weu` |
| Action Group (P3) | `ag-monitoring-p3-<regio>` | `ag-monitoring-p3-weu` |
| Logic App | `logic-autotask-monitoring-<regio>` | `logic-autotask-monitoring-weu` |
| Budget | `bud-monitoring-<klantcode>` | `bud-monitoring-pilot` |
| Alert Processing Rule | `apr-maintenance-<klantcode>` | `apr-maintenance-pilot` |
| Policy Set Definition | `psi-diag-settings-<klantcode>` | `psi-diag-settings-pilot` |
| Policy Assignment | `pa-diag-settings-<klantcode>` | `pa-diag-settings-pilot` |
| Data Collection Rule (VM) | `dcr-vm-<tier>-<regio>` | `dcr-vm-managed-weu` |
| Data Collection Rule (Storage) | `dcr-storage-<tier>-<regio>` | `dcr-storage-managed-weu` |
| Data Collection Rule (RSV) | `dcr-rsv-<tier>-<regio>` | `dcr-rsv-managed-weu` |
| Data Collection Rule (VPN GW) | `dcr-vpngw-<tier>-<regio>` | `dcr-vpngw-managed-weu` |
| Data Collection Rule (AVD) | `dcr-avd-<tier>-<regio>` | `dcr-avd-advanced-weu` |
| Recovery Services Vault | `rsv-<klantcode>-<env>-<regio>` | `rsv-pilot-mock-weu` |
| Storage account | `st<klantcode><env><regio>` (no hyphens, max 24 chars) | `stpilotmockweu` |
| Virtual Machine | `vm-<klantcode>-<env>-<regio>-<###>` | `vm-pilot-mock-weu-001` |
| VPN Gateway | `vgw-<klantcode>-<env>-<regio>-<###>` | `vgw-pilot-mock-weu-001` |
| AVD Host Pool | `vdpool-<klantcode>-<env>-<regio>-<###>` | `vdpool-pilot-mock-weu-001` |
| Virtual Network | `vnet-<klantcode>-<env>-<regio>` | `vnet-pilot-mock-weu` |
| Public IP | `pip-<purpose>-<klantcode>-<env>-<regio>` | `pip-vgw-pilot-mock-weu` |
| Network Interface | `nic-<vmname>` | `nic-vm-pilot-mock-weu-001` |
| Lighthouse definition | `lighthouse-monitoring-<klantcode>` (as GUID seed) | — |

## Tags (required on all resources)

| Tag | Value | Description |
|---|---|---|
| `Environment` | `monitoring` / `mock` / `production` | Resource purpose |
| `ManagedBy` | `platform-team` | Owning team |
| `KlantCode` | e.g. `pilot` | Customer identifier |
| `Tier` | `Essential` / `Managed` / `Advanced` | Monitoring tier |
| `baseline-version` | e.g. `0.1-pilot` | Baseline release version |
| `CostCenter` | e.g. `monitoring-pilot` | Cost attribution |

## Alert naming patterns

Alert rules follow: `alert-<resourcetype>-<signal>-<priority>-<klantcode>`

| Example | Description |
|---|---|
| `alert-servicehealth-incident-pilot` | Service Health incident |
| `alert-rsv-backup-failed-p2-pilot` | RSV backup failure P2 |
| `alert-vpngw-tunnel-down-p1-pilot` | VPN tunnel down P1 |
| `alert-vm-heartbeat-p1-pilot` | VM heartbeat lost P1 |
| `alert-activity-rbac-change-p2-pilot` | RBAC change P2 |
