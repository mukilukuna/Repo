# Phase 1 – Monitoring Baseline: Validatieresultaten

**Klant:** pilot  
**Datum:** 2026-06-19  
**Tier:** Advanced  
**Abonnement:** `098e34b6-d88e-447e-ba9a-245275343d63` (Visual Studio Enterprise – MPN)  
**Uitgevoerd door:** IT Synergy – platform team  

---

## 1. Samenvatting

De monitoring baseline (Chores 1-10) is succesvol gedeployed in de West Europe regio. Alle 26 monitoring-resources staan op `Succeeded`. De 9 mock-workloadresources (Chore 2) zijn eveneens operationeel.

| Onderdeel | Status |
|-----------|--------|
| Mock-omgeving (`rg-pilot-mock-weu`) | ✅ Succesvol |
| Monitoring platform (`rg-pilot-platform-weu`) | ✅ Succesvol |
| Log Analytics Workspace | ✅ Actief |
| Alert Rules (20 regels) | ✅ Actief |
| Action Groups (P1/P2/P3) | ✅ Actief |
| Logic App (Autotask stub) | ✅ Actief |
| Alert Processing Rule (maintenance) | ✅ Actief |
| Budget (€25/maand) | ✅ Actief |
| DCR – VM | ✅ Actief |

---

## 2. Deployed Resources

### 2.1 Mock Workload (`rg-pilot-mock-weu`)

| Resource | Type | Status |
|----------|------|--------|
| `vnet-pilot-mock-weu` | Virtual Network | ✅ Succeeded |
| `pip-vgw-pilot-mock-weu` | Public IP (Standard, zone-redundant) | ✅ Succeeded |
| `vgw-pilot-mock-weu-001` | VPN Gateway (VpnGw1AZ) | ✅ Succeeded |
| `rsv-pilot-mock-weu` | Recovery Services Vault | ✅ Succeeded |
| `vm-pilot-mock-weu-001` | Windows Server VM (B2s) | ✅ Succeeded |
| `nic-vm-pilot-mock-weu-001` | Network Interface | ✅ Succeeded |
| `stpilotmockweu` | Storage Account + FSLogix share | ✅ Succeeded |
| `vdpool-pilot-mock-weu-001` | AVD Host Pool | ✅ Succeeded |
| VM OS disk | Managed Disk | ✅ Succeeded |

**Backup verificatie:** VM `vm-pilot-mock-weu-001` geregistreerd in RSV, Protection Status: Healthy  
**FSLogix verificatie:** Share `fslogix` aanwezig in `stpilotmockweu`

### 2.2 Monitoring Platform (`rg-pilot-platform-weu`)

| Resource | Type |
|----------|------|
| `log-pilot-platform-weu` | Log Analytics Workspace (PerGB2018, 30 dagen retentie, 1 GB/dag cap) |
| `dcr-vm-managed-weu` | Data Collection Rule – VM (perf counters + Windows Event Log) |
| `logic-autotask-monitoring-weu` | Logic App – Autotask webhook stub (Phase 1: log-only) |
| `ag-monitoring-p1-weu` | Action Group P1 (webhook + email oncall) |
| `ag-monitoring-p2-weu` | Action Group P2 (webhook only) |
| `ag-monitoring-p3-weu` | Action Group P3 (email reporting) |
| `apr-maintenance-pilot` | Alert Processing Rule – suppressie zondag 02:00-06:00 UTC |
| `bud-monitoring-pilot` | Budget €25/maand, drempels 80/90/100% |

---

## 3. Alert Rules Overzicht

### Metric Alerts

| # | Naam | Bron | Drempel | Prioriteit |
|---|------|------|---------|-----------|
| 13 | Storage availability | `stpilotmockweu` | < 99,9% over 5 min | P1 |
| 14 | Storage capacity 80% | `stpilotmockweu` | > 87,9 TB | P3 |
| 15 | Storage capacity 95% | `stpilotmockweu` | > 104,5 TB | P2 |
| 16 | Azure Files throttling | `stpilotmockweu/fileServices/default` | > 0 SuccessWithThrottling over 10 min | P2 |
| 9 | VPN GW bandwidth | `vgw-pilot-mock-weu-001` | Dynamisch (Medium gevoeligheid) | P3 |

### Scheduled Query Rules (Log-based)

| # | Naam | Query bron | Frequentie | Prioriteit |
|---|------|------------|-----------|-----------|
| 4 | RSV backup mislukt (P2) | AddonAzureBackupJobs | 1 uur | P2 |
| 5 | RSV backup 2x mislukt (P1) | AddonAzureBackupJobs | 1 uur | P1 |
| 10 | AVD hosts unavailable | WVDErrors | 5 min | P1 |
| 11 | AVD connection errors | WVDConnections | 15 min | P2 |
| 12 | AVD scaling failed | WVDErrors (ScalingPlan) | 1 uur | P2 |
| 17 | VM heartbeat lost | Heartbeat | 5 min | P1 |
| 20 | Policy non-compliant | AzureActivity | 1 uur | P3 |
| LAW | Daily cap warning 80% | Usage | 1 uur | P3 |

### Activity Log Alerts

| # | Naam | Conditie | Prioriteit |
|---|------|----------|-----------|
| 1 | Service Health incident | category=ServiceHealth, type=Incident/ActionRequired | P2 |
| 2 | Resource Health Unavailable | currentHealthStatus=Unavailable | P1 |
| 3 | Resource Health Degraded | currentHealthStatus=Degraded | P2 |
| 6 | RSV soft delete gewijzigd | backupconfig/write | P1 |
| 18 | Kritieke resource verwijderd | VM delete | P1 |
| 19 | RBAC wijziging | roleAssignments/write | P2 |

---

## 4. Bekende Aanpassingen voor Pilot (VS Subscription)

De volgende afwijkingen gelden voor de pilot op de Visual Studio Enterprise-abonnement en worden gecorrigeerd bij productie-uitrol:

| Aanpassing | Reden | Productie actie |
|------------|-------|----------------|
| `deployPolicy = false` | VS subscription heeft geen built-in DINE policy definitions | Inschakelen op productie EA/MCA subscription |
| Lighthouse overgeslagen | Pilot draait in eigen tenant | `monitoringReaderGroupId` + `managingTenantId` invullen |
| VPN GW SKU: VpnGw1AZ | Basic/VpnGw1 deprecated in West Europe | VpnGw1AZ is juiste productie-SKU |
| SMB Multichannel uitgeschakeld | Niet ondersteund op VS subscription storage | Klant specifiek evalueren |
| Budget €25/maand | Conservatieve startwaarde voor pilot | Kalibreren na 4 weken observatie (zie §6) |
| Alert Processing Rule: `status` property | Bicep type definitie afwijking (BCP037 warning) | Werkt correct in Azure, oplossen bij Bicep CLI update |

---

## 5. Validatiechecklist

### Chore 2 – Mock omgeving

- [x] Virtual Network aangemaakt in West Europe
- [x] VPN Gateway (VpnGw1AZ) actief
- [x] Recovery Services Vault actief
- [x] VM geregistreerd als backup item (Protection: Healthy)
- [x] Storage account + FSLogix share (`fslogix`) aanwezig
- [x] AVD Host Pool aangemaakt

### Chore 3 – Log Analytics

- [x] Workspace `log-pilot-platform-weu` actief in West Europe
- [x] SKU: PerGB2018
- [x] Retentie: 30 dagen
- [x] Daily cap: 1 GB (conservatief – kalibreren na Phase 1)
- [x] Daily cap warning alert actief (vuurt bij 80% van cap)

### Chores 4-5 – DCR & Alert Rules

- [x] VM DCR actief (performance counters + Windows Event Log)
- [x] 20 alert rules actief (5 metric, 8 scheduled query, 6 activity log, 1 service health)
- [x] Alle alerts gekoppeld aan correcte action groups

### Chore 6 – Alert Processing Rules

- [x] Maintenance window suppressie actief (zondag 02:00-06:00 UTC)

### Chore 7 – Budget

- [x] Budget `bud-monitoring-pilot` actief (€25/maand)
- [x] Drempels: 80% (P3), 90% (P3), 100% (P2)

### Chore 8 – Policy

- [ ] Uitgesteld — VS subscription heeft geen built-in DINE policy definitions  
  → Geplanned voor productie-uitrol

### Chore 9 – Lighthouse

- [ ] Uitgesteld — pilot draait in eigen tenant  
  → Invullen bij eerste klantomgeving

### Chore 10 – End-to-end deployment

- [x] `Deploy-Monitoring.ps1` succesvol uitgevoerd (exit code 0)
- [x] Alle 26 platform-resources status: Succeeded
- [x] Deployment naam: `monitoring-pilot-20260619-1356`

---

## 6. Aanbevelingen na Phase 1 Observatie (4 weken)

### Budget kalibratie
Na 4 weken data verzamelen:
1. Controleer `Azure Monitor > Kosten` voor werkelijk ingestion volume
2. Bereken: `werkelijke kosten × 1,20` = nieuw budget
3. Pas `budgetAmountEur` aan in `monitoring.bicepparam`
4. Herdeployeer via `Deploy-Monitoring.ps1`

### Daily cap kalibratie
1. Voer in Log Analytics uit:
   ```kusto
   Usage
   | where TimeGenerated > ago(7d)
   | summarize AvgGB = avg(Quantity) / 1000 by bin(TimeGenerated, 1d)
   | order by TimeGenerated desc
   ```
2. Stel daily cap in op `piekdag × 1,50`
3. Pas `dailyCapGb` aan in `monitoring.bicepparam`

### Alert finetuning
- Controleer welke alerts gevuurd hebben (Azure Monitor > Alerts > History)
- Pas drempels bij voor storage capacity (momenteel 100 TB standaard)
- Overweeg extra alert rules op basis van observaties

### Volgende stappen voor productie
1. Klantomgeving aanmaken in `Bicep/infra/customers/<klantCode>/`
2. `deployPolicy = true` instellen
3. Lighthouse parameters invullen
4. `Deploy-Monitoring.ps1 -KlantCode <klantCode>` uitvoeren

---

## 7. Deployment Details

| Gegeven | Waarde |
|---------|--------|
| Deployment naam | `monitoring-pilot-20260619-1356` |
| Tijdstip | 2026-06-19T11:57:41 UTC |
| Duur | 41,9 seconden |
| Template hash | `9226003558791819774` |
| Bicep CLI versie | v0.44.1 |
| Azure CLI versie | v2.87.0 |
| Deployment mode | Incremental |
