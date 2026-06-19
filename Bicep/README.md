# Azure Monitoring Baseline – Bicep Project

Bicep-as-code implementation of the IT Synergy Azure Monitoring Baseline. Based on the Technisch Ontwerp (TO) and Chore specifications.

## Folder structure

```
Bicep/
├── infra/
│   ├── platform/
│   │   └── modules/
│   │       └── monitoring/           ← Reusable monitoring modules
│   │           ├── monitoring.bicep          Main assembly (call this)
│   │           ├── log-analytics.bicep       Log Analytics Workspace + daily cap
│   │           ├── data-collection-rules.bicep DCRs per resource type / tier
│   │           ├── alert-rules.bicep         20 alert rules from baseline table
│   │           ├── alert-processing-rules.bicep Maintenance window suppression
│   │           ├── action-groups.bicep       P1/P2/P3 Action Groups + webhook
│   │           ├── autotask-logicapp.bicep   Logic App stub (Phase 1: log only)
│   │           ├── budget.bicep              Azure Budget + cost alerts
│   │           ├── policy.bicep              DINE policy for diagnostic settings
│   │           └── lighthouse-rbac.bicep     Lighthouse delegation template
│   ├── mock/
│   │   └── resources.bicep           Mock workload resources for pilot testing
│   └── customers/
│       └── pilot/
│           └── monitoring.bicepparam VS subscription pilot parameter file
├── scripts/
│   ├── Deploy-Monitoring.ps1         Deployment wrapper (build → what-if → deploy)
│   └── Deploy-MockResources.ps1      Mock environment deployment wrapper
└── docs/
    ├── naming.md                     CAF naming conventions for all resource types
    └── mock-environment.md           Mock environment limitations and cost tips
```

## Monitoring tiers

| Tier | Covers | Typical customer |
|---|---|---|
| **Essential** | Service Health, Resource Health, Activity Log, budget alert | All managed customers |
| **Managed** | + RSV backup, VPN Gateway, Storage accounts, VM heartbeat | Customers with managed Azure platform |
| **Advanced** | + AVD host pool, scaling plan, Azure Files throttling, dynamic thresholds | Customers with AVD |

## Adding a new customer

1. Create `infra/customers/<klantcode>/monitoring.bicepparam` (copy from `pilot/`).
2. Fill in `klantCode`, `tier`, `monitoredResourceGroupId`, email addresses.
3. Create the monitoring resource group: `az group create -n rg-<klantcode>-platform-weu -l westeurope`.
4. Run: `.\scripts\Deploy-Monitoring.ps1 -KlantCode <klantcode> -ResourceGroup rg-<klantcode>-platform-weu -SubscriptionId <sub-id> -WhatIf`
5. Review what-if output, then redeploy without `-WhatIf` to deploy.

## Deploying the pilot

```powershell
cd C:\Repo\Bicep

# Validate only
.\scripts\Deploy-Monitoring.ps1 `
    -KlantCode pilot `
    -ResourceGroup rg-pilot-platform-weu `
    -SubscriptionId 098e34b6-d88e-447e-ba9a-245275343d63 `
    -WhatIf

# Deploy mock resources first (Chore 2)
$pw = Read-Host -AsSecureString "VM admin password"
.\scripts\Deploy-MockResources.ps1 `
    -SubscriptionId 098e34b6-d88e-447e-ba9a-245275343d63 `
    -AdminPassword $pw

# Deploy monitoring baseline
.\scripts\Deploy-Monitoring.ps1 `
    -KlantCode pilot `
    -ResourceGroup rg-pilot-platform-weu `
    -SubscriptionId 098e34b6-d88e-447e-ba9a-245275343d63
```

## Phase 1 (observation mode)

After deployment, alerts fire and are logged by the Logic App stub — no Autotask tickets are created. Run in observation mode for 2 weeks (per TO section 7) before Phase 2 activation.

**Phase 2 activation checklist (open items from TO):**
- [ ] TO open item 2: Autotask queue/team names decided → fill in `autotask-logicapp.bicep` stub
- [ ] TO open item 3: Entra group Object IDs for Lighthouse → fill in `lighthouse-rbac.bicep` parameters
- [ ] Calibrate budget based on Phase 1 measured ingestion costs (Chore 11)
- [ ] Tune alert thresholds with false-positive rate > 20% (Chore 11)

## Alert baseline table (summary)

| # | Resource | Signal | Priority | Alert type |
|---|---|---|---|---|
| 1 | Service Health | Incident in region | P2 | Activity Log (ServiceHealth) |
| 2 | Resource Health | Unavailable | P1 | Activity Log (ResourceHealth) |
| 3 | Resource Health | Degraded | P2 | Activity Log (ResourceHealth) |
| 4 | RSV | Backup failed (1x) | P2 | Log alert |
| 5 | RSV | Backup failed (2x) | P1 | Log alert |
| 6 | RSV | Soft delete changed | P1 | Activity Log |
| 7 | VPN GW | Tunnel offline (no redundancy) | P1 | Metric |
| 8 | VPN GW | Tunnel offline (redundant active) | P2 | Metric |
| 9 | VPN GW | Bandwidth high | P3 | Metric (dynamic) |
| 10 | AVD | Hosts unavailable | P1 | Log alert |
| 11 | AVD | Connection errors high | P2 | Log alert |
| 12 | AVD | Scaling action failed | P2 | Log alert |
| 13 | Storage | Availability < 99.9% | P1 | Metric |
| 14 | Storage | Capacity > 80% | P3 | Metric |
| 15 | Storage | Capacity > 95% | P2 | Metric |
| 16 | Azure Files | Transaction throttling | P2 | Metric |
| 17 | VM | Heartbeat lost | P1 | Log alert |
| 18 | Activity Log | Critical resource deleted | P1 | Activity Log |
| 19 | Activity Log | RBAC change | P2 | Activity Log |
| 20 | Policy | Non-compliant resource | P3 | Log alert |
| 21 | Budget | Reached 80% | P3 | Budget alert (budget.bicep) |
| 22 | Budget | Reached 100% / anomaly | P2 | Budget alert (budget.bicep) |

Rules 10–12 and 16 are **Advanced tier only**. Rules 4–9 and 13–15 are **Managed+ tier**. Rules 1–3, 18–22 are **all tiers**.
