// ============================================================
// Module: monitoring.bicep
// Purpose: Top-level assembly. Calls every sub-module in the
//          correct dependency order and chains parameters.
//          Customers only need to fill one .bicepparam file.
// Chore: 10
// ============================================================

@description('Customer identifier code (lowercase, max 8 chars).')
param klantCode string

@description('Azure region for all resources. Must be westeurope for naming convention compliance (weu suffix).')
@allowed(['westeurope'])
param location string = 'westeurope'

@description('Monitoring tier: Essential / Managed / Advanced.')
@allowed(['Essential', 'Managed', 'Advanced'])
param tier string

@description('Resource ID of the customer workload resource group to monitor.')
param monitoredResourceGroupId string

@description('Monthly monitoring budget in EUR.')
@minValue(1)
param budgetAmountEur int = 25

@description('On-call email address (receives P1 alerts).')
param onCallEmail string

@description('Reporting email address (receives P3 alerts).')
param reportingEmail string

@description('Entra group Object ID for Monitoring Reader (Lighthouse). Leave empty to skip Lighthouse.')
param monitoringReaderGroupId string = ''

@description('Entra group Object ID for Monitoring Contributor (Lighthouse). Leave empty to skip Lighthouse.')
param monitoringContributorGroupId string = ''

@description('IT Synergy managing tenant ID (Lighthouse). Leave empty to skip Lighthouse.')
param managingTenantId string = ''

@description('Day of week for maintenance window alert suppression.')
@allowed(['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'])
param maintenanceWindowDayOfWeek string = 'Sunday'

@description('Maintenance window start time (HH:mm UTC).')
param maintenanceWindowStart string = '02:00'

@description('Maintenance window end time (HH:mm UTC).')
param maintenanceWindowEnd string = '06:00'

@description('Optional: Resource ID of the VPN Gateway in the monitored RG. Required for VPN Gateway metric alerts.')
param vpnGatewayResourceId string = ''

@description('Optional: Resource ID of the primary Storage Account to monitor. Required for Storage metric alerts.')
param storageAccountResourceId string = ''

// Whether to deploy Lighthouse (requires all three Lighthouse params to be non-empty)
var deployLighthouse = !empty(monitoringReaderGroupId) && !empty(monitoringContributorGroupId) && !empty(managingTenantId)

var commonTags = {
  Environment: 'monitoring'
  ManagedBy: 'platform-team'
  KlantCode: klantCode
  Tier: tier
  'baseline-version': '0.1-pilot'
}

// ── 1. Log Analytics Workspace ────────────────────────────────
module law './log-analytics.bicep' = {
  name: 'deploy-law-${klantCode}'
  params: {
    klantCode: klantCode
    location: location
    tags: commonTags
  }
}

// ── 2. Data Collection Rules ──────────────────────────────────
module dcr './data-collection-rules.bicep' = {
  name: 'deploy-dcr-${klantCode}'
  params: {
    workspaceId: law.outputs.workspaceId
    tier: tier
    location: location
    tags: commonTags
  }
}

// ── 3. Logic App (must come before Action Groups to get webhook URI) ──
module logicApp './autotask-logicapp.bicep' = {
  name: 'deploy-logicapp-${klantCode}'
  params: {
    location: location
    workspaceId: law.outputs.workspaceId
    workspaceCustomerId: law.outputs.workspaceCustomerId
    klantCode: klantCode
    tags: commonTags
  }
}

// ── 4. Action Groups ──────────────────────────────────────────
module actionGroups './action-groups.bicep' = {
  name: 'deploy-ag-${klantCode}'
  params: {
    logicAppWebhookUri: logicApp.outputs.logicAppWebhookUri
    onCallEmail: onCallEmail
    reportingEmail: reportingEmail
    tags: commonTags
  }
}

// ── 5. Alert Rules ────────────────────────────────────────────
module alertRules './alert-rules.bicep' = {
  name: 'deploy-alert-rules-${klantCode}'
  params: {
    workspaceId: law.outputs.workspaceId
    tier: tier
    location: location
    actionGroupP1Id: actionGroups.outputs.actionGroupP1Id
    actionGroupP2Id: actionGroups.outputs.actionGroupP2Id
    actionGroupP3Id: actionGroups.outputs.actionGroupP3Id
    klantCode: klantCode
    tags: commonTags
    vpnGatewayResourceId: vpnGatewayResourceId
    storageAccountResourceId: storageAccountResourceId
  }
}

// ── 6. Alert Processing Rules ─────────────────────────────────
module apr './alert-processing-rules.bicep' = {
  name: 'deploy-apr-${klantCode}'
  params: {
    targetResourceGroupId: monitoredResourceGroupId
    klantCode: klantCode
    maintenanceWindowStart: maintenanceWindowStart
    maintenanceWindowEnd: maintenanceWindowEnd
    maintenanceWindowDayOfWeek: maintenanceWindowDayOfWeek
    tags: commonTags
  }
}

// ── 7. Budget ─────────────────────────────────────────────────
module budget './budget.bicep' = {
  name: 'deploy-budget-${klantCode}'
  params: {
    klantCode: klantCode
    budgetAmountEur: budgetAmountEur
    actionGroupP2Id: actionGroups.outputs.actionGroupP2Id
    actionGroupP3Id: actionGroups.outputs.actionGroupP3Id
  }
}

// Deploy policy to the monitored RG (not the monitoring RG)
var monitoredSubId = split(monitoredResourceGroupId, '/')[2]
var monitoredRgName = split(monitoredResourceGroupId, '/')[4]

// ── 8. Policy ─────────────────────────────────────────────────
module policy './policy.bicep' = {
  name: 'deploy-policy-${klantCode}'
  scope: resourceGroup(monitoredSubId, monitoredRgName)
  params: {
    klantCode: klantCode
    workspaceId: law.outputs.workspaceId
    location: location
  }
}

// ── 9. Lighthouse RBAC (optional) ────────────────────────────
module lighthouse './lighthouse-rbac.bicep' = if (deployLighthouse) {
  name: 'deploy-lighthouse-${klantCode}'
  params: {
    managingTenantId: managingTenantId
    monitoringReaderGroupId: monitoringReaderGroupId
    monitoringContributorGroupId: monitoringContributorGroupId
    klantCode: klantCode
  }
}

// ── Outputs ──────────────────────────────────────────────────
@description('Log Analytics Workspace resource ID.')
output workspaceId string = law.outputs.workspaceId

@description('P1 Action Group resource ID.')
output actionGroupP1Id string = actionGroups.outputs.actionGroupP1Id

@description('P2 Action Group resource ID.')
output actionGroupP2Id string = actionGroups.outputs.actionGroupP2Id

@description('P3 Action Group resource ID.')
output actionGroupP3Id string = actionGroups.outputs.actionGroupP3Id
