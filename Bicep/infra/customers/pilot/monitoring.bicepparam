using '../../platform/modules/monitoring/monitoring.bicep'

// ── Pilot customer – Visual Studio subscription ───────────────
// Tier: Advanced (exercises all alert rules during Phase 1)
// Lighthouse: skipped (pilot runs in IT Synergy's own subscription,
//             not a delegated customer tenant)

param klantCode = 'pilot'
param location = 'westeurope'
param tier = 'Advanced'

// Resource group where mock workload resources live (Chore 2)
// Update this value after deploying rg-pilot-mock-weu
param monitoredResourceGroupId = '/subscriptions/098e34b6-d88e-447e-ba9a-245275343d63/resourceGroups/rg-pilot-mock-weu'

// VPN Gateway deployed in Chore 2 — enables VPN metric alerts
param vpnGatewayResourceId = '/subscriptions/098e34b6-d88e-447e-ba9a-245275343d63/resourceGroups/rg-pilot-mock-weu/providers/Microsoft.Network/virtualNetworkGateways/vgw-pilot-mock-weu-001'

// Storage account deployed in Chore 2 — enables Storage metric alerts
param storageAccountResourceId = '/subscriptions/098e34b6-d88e-447e-ba9a-245275343d63/resourceGroups/rg-pilot-mock-weu/providers/Microsoft.Storage/storageAccounts/stpilotmockweu'

// Budget: conservative starting point; calibrate after Phase 1 (Chore 11)
param budgetAmountEur = 25

// Email addresses – replace with real addresses before first deployment
param onCallEmail = 'oncall@itsynergy.nl'
param reportingEmail = 'reporting@itsynergy.nl'

// Policy assignments require Production subscription. Skipped for VS pilot.
param deployPolicy = false

// Lighthouse: left empty → module is skipped for pilot
param monitoringReaderGroupId = ''
param monitoringContributorGroupId = ''
param managingTenantId = ''

// Maintenance window: Sunday 02:00–06:00 UTC (default)
param maintenanceWindowDayOfWeek = 'Sunday'
param maintenanceWindowStart = '02:00:00'
param maintenanceWindowEnd = '06:00:00'
