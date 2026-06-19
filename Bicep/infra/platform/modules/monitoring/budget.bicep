// ============================================================
// Module: budget.bicep
// Purpose: Deploy Azure Budget with 80/90/100% cost alerts and
//          a subscription-level cost anomaly alert.
//          Budget alerts 21-22 from the baseline table.
//
// NOTE: The default budget amount of EUR 25/month is a
//       conservative starting point for a small managed customer.
//       Calibrate after Phase 1 based on measured ingestion costs
//       + 20% margin. See Chore 11 for calibration guidance.
// Chore: 7
// ============================================================

@description('Customer identifier code.')
param klantCode string

@description('Monthly budget amount in EUR.')
@minValue(1)
param budgetAmountEur int = 25

@description('Resource ID of the P2 Action Group (100% alert + anomaly).')
param actionGroupP2Id string

@description('Resource ID of the P3 Action Group (80% and 90% alerts).')
param actionGroupP3Id string

@description('Start date for the budget period in format YYYY-MM-DD.')
param budgetStartDate string = '2026-06-01'

// ── Monitoring Resource Group Budget ─────────────────────────
// Scope: current resource group (the monitoring RG, not the whole subscription)
resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: 'bud-monitoring-${klantCode}'
  properties: {
    category: 'Cost'
    amount: budgetAmountEur
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: budgetStartDate // Set to beginning of current month; update in monitoring.bicepparam each new year
    }
    notifications: {
      // 80% warning → P3 (reporting email only)
      At80Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        thresholdType: 'Actual'
        contactEmails: []
        contactGroups: [actionGroupP3Id]
      }
      // 90% warning → P3
      At90Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 90
        thresholdType: 'Actual'
        contactEmails: []
        contactGroups: [actionGroupP3Id]
      }
      // 100% reached → P2 (webhook to Logic App)
      At100Percent: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Actual'
        contactEmails: []
        contactGroups: [actionGroupP2Id]
      }
    }
  }
}

// ── Cost Anomaly Alert (subscription scope) ──────────────────
// This resource must be deployed at subscription scope via a
// separate deployment in monitoring.bicep (targetScope = 'subscription').
// It is defined here as a module output reference for documentation.
// The actual anomaly alert is in monitoring.bicep under subscriptionScope deployment.
//
// Microsoft.CostManagement/scheduledActions is the resource type
// for anomaly alerts (2023-11-01 API).

// ── Outputs ──────────────────────────────────────────────────
@description('Resource ID of the budget.')
output budgetId string = budget.id

@description('Budget name for reference in Chore 11 calibration.')
output budgetName string = budget.name
