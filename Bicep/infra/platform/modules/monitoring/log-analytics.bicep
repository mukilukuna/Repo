// ============================================================
// Module: log-analytics.bicep
// Purpose: Deploy Log Analytics Workspace with daily cap and
//          retention settings. Foundation for all other modules.
// Chore: 3
// ============================================================

@description('Customer identifier code (lowercase, max 8 chars).')
param klantCode string

@description('Azure region for deployment. Must be westeurope.')
@allowed(['westeurope'])
param location string

@description('Interactive retention period in days.')
@minValue(30)
@maxValue(730)
param retentionDays int = 30

@description('Daily ingestion cap in GB. Set after Phase 1 calibration.')
@minValue(1)
param dailyCapGb int = 1

@description('Resource tags to apply.')
param tags object = {}

// ── Workspace ─────────────────────────────────────────────────
resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${klantCode}-platform-weu'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
    workspaceCapping: {
      dailyQuotaGb: dailyCapGb
    }
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ── Daily cap warning alert (fires at 80 % of the daily cap) ─
resource capWarningAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-law-daily-cap-warning-${klantCode}'
  location: location
  tags: tags
  properties: {
    displayName: '[${klantCode}] Log Analytics daily cap at 80%'
    description: 'Fires when the workspace is approaching the daily ingestion cap. Investigate data sources before the cap is hit and logs stop flowing.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    scopes: [workspace.id]
    criteria: {
      allOf: [
        {
          query: '''
            Usage
            | where TimeGenerated > ago(1d)
            | summarize IngestedGB = sum(Quantity) / 1000
            | where IngestedGB >= ${dailyCapGb} * 0.8
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThanOrEqual'
          threshold: 1
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
  }
}

// ── Outputs ────────────────────────────────────────────────────
@description('Full resource ID of the Log Analytics Workspace.')
output workspaceId string = workspace.id

@description('Log Analytics Workspace ID (customer / workspace GUID).')
output workspaceCustomerId string = workspace.properties.customerId

@description('Log Analytics Workspace name.')
output workspaceName string = workspace.name
