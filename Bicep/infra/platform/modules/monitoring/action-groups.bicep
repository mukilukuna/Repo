// ============================================================
// Module: action-groups.bicep
// Purpose: Deploy three Action Groups for P1 / P2 / P3 alert
//          routing. P1 and P2 use the Logic App webhook.
//          P3 sends email only (periodic reporting, no ticket).
// Chore: 6
// ============================================================

@description('HTTPS webhook URI of the Autotask Logic App.')
param logicAppWebhookUri string

@description('Email address of the on-call engineer (receives P1 alerts).')
param onCallEmail string

@description('Email address for reporting (receives P3 alerts).')
param reportingEmail string

@description('Resource tags to apply.')
param tags object = {}

// ── P1 Action Group – webhook + on-call email ─────────────────
resource agP1 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-monitoring-p1-weu'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'mon-p1'
    enabled: true
    webhookReceivers: [
      {
        name: 'autotask-webhook-p1'
        serviceUri: logicAppWebhookUri
        useCommonAlertSchema: true
      }
    ]
    emailReceivers: [
      {
        name: 'oncall-p1'
        emailAddress: onCallEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// ── P2 Action Group – webhook only ───────────────────────────
resource agP2 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-monitoring-p2-weu'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'mon-p2'
    enabled: true
    webhookReceivers: [
      {
        name: 'autotask-webhook-p2'
        serviceUri: logicAppWebhookUri
        useCommonAlertSchema: true
      }
    ]
  }
}

// ── P3 Action Group – reporting email only ───────────────────
resource agP3 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-monitoring-p3-weu'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'mon-p3'
    enabled: true
    emailReceivers: [
      {
        name: 'reporting-p3'
        emailAddress: reportingEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// ── Outputs ───────────────────────────────────────────────────
@description('Resource ID of the P1 Action Group.')
output actionGroupP1Id string = agP1.id

@description('Resource ID of the P2 Action Group.')
output actionGroupP2Id string = agP2.id

@description('Resource ID of the P3 Action Group.')
output actionGroupP3Id string = agP3.id
