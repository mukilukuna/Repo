// ============================================================
// Module: alert-rules.bicep
// Purpose: Deploy the 20 alert rules from the monitoring baseline
//          table (rules 21-22 for budget are in budget.bicep).
//          Alert types: Metric, Log (Scheduled Query), Activity
//          Log, Resource Health, Service Health.
// Chore: 5
// ============================================================

@description('Full resource ID of the Log Analytics Workspace.')
param workspaceId string

@description('Resource ID of the resource group being monitored (customer workload RG).')
param targetResourceGroupId string

@description('Deployment tier.')
@allowed(['Essential', 'Managed', 'Advanced'])
param tier string

@description('Azure region for deployment. Must be westeurope.')
@allowed(['westeurope'])
param location string

@description('Resource ID of the P1 Action Group.')
param actionGroupP1Id string

@description('Resource ID of the P2 Action Group.')
param actionGroupP2Id string

@description('Resource ID of the P3 Action Group.')
param actionGroupP3Id string

@description('Customer identifier code.')
param klantCode string

@description('Resource tags to apply.')
param tags object = {}

var isManagedOrAbove = tier != 'Essential'
var isAdvanced = tier == 'Advanced'

// ── 1. Service Health alert (P2) ──────────────────────────────
resource alertServiceHealth 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alert-servicehealth-incident-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [subscription().id]
    condition: {
      allOf: [
        { field: 'category', equals: 'ServiceHealth' }
        { field: 'properties.incidentType', containsAny: ['Incident', 'ActionRequired'] }
      ]
    }
    actions: {
      actionGroups: [
        { actionGroupId: actionGroupP2Id }
      ]
    }
    description: 'Fires on any Azure Service Health incident affecting the customer region or services.'
  }
}

// ── 2. Resource Health – Unavailable (P1) ─────────────────────
resource alertResourceHealthUnavailable 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alert-resourcehealth-unavailable-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [subscription().id]
    condition: {
      allOf: [
        { field: 'category', equals: 'ResourceHealth' }
        { field: 'properties.currentHealthStatus', equals: 'Unavailable' }
        { field: 'properties.previousHealthStatus', containsAny: ['Available', 'Unknown'] }
      ]
    }
    actions: {
      actionGroups: [
        { actionGroupId: actionGroupP1Id }
      ]
    }
    description: 'Fires when any resource transitions to Unavailable state (sustained > 5 min enforced by APR).'
  }
}

// ── 3. Resource Health – Degraded (P2) ───────────────────────
resource alertResourceHealthDegraded 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alert-resourcehealth-degraded-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [subscription().id]
    condition: {
      allOf: [
        { field: 'category', equals: 'ResourceHealth' }
        { field: 'properties.currentHealthStatus', equals: 'Degraded' }
      ]
    }
    actions: {
      actionGroups: [
        { actionGroupId: actionGroupP2Id }
      ]
    }
    description: 'Fires when any resource transitions to Degraded state (sustained > 15 min).'
  }
}

// ── 4. RSV Backup job failed – first occurrence (P2) ─────────
resource alertRsvBackupFailed 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (isManagedOrAbove) {
  name: 'alert-rsv-backup-failed-p2-${klantCode}'
  location: location
  tags: tags
  properties: {
    displayName: '[${klantCode}] RSV backup job failed (P2)'
    description: 'Fires on first backup job failure for any protected item.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            AddonAzureBackupJobs
            | where JobOperation == "Backup"
            | where JobStatus == "Failed"
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupP2Id]
    }
  }
}

// ── 5. RSV Backup job failed – 2x consecutive (P1) ───────────
resource alertRsvBackupFailedP1 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (isManagedOrAbove) {
  name: 'alert-rsv-backup-failed-p1-${klantCode}'
  location: location
  tags: tags
  properties: {
    displayName: '[${klantCode}] RSV backup job failed 2x consecutive (P1)'
    description: 'Fires when the same protected item fails backup twice in a row.'
    severity: 0
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT2H'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            AddonAzureBackupJobs
            | where JobOperation == "Backup"
            | where JobStatus == "Failed"
            | summarize Failures = count() by BackupItemUniqueId
            | where Failures >= 2
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupP1Id]
    }
  }
}

// ── 6. RSV Soft delete / immutability changed (P1) ───────────
resource alertRsvSoftDelete 'Microsoft.Insights/activityLogAlerts@2020-10-01' = if (isManagedOrAbove) {
  name: 'alert-rsv-softdelete-changed-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [subscription().id]
    condition: {
      allOf: [
        { field: 'category', equals: 'Administrative' }
        { field: 'operationName', containsAny: [
          'Microsoft.RecoveryServices/vaults/backupconfig/write'
          'Microsoft.RecoveryServices/vaults/write'
        ]}
        { field: 'status', equals: 'Succeeded' }
      ]
    }
    actions: {
      actionGroups: [
        { actionGroupId: actionGroupP1Id }
      ]
    }
    description: 'Fires when RSV soft delete or immutability settings are changed.'
  }
}

// ── 7. VPN Gateway – tunnel offline, no redundant tunnel (P1) ─
resource alertVpnTunnelDownP1 'Microsoft.Insights/metricAlerts@2018-03-01' = if (isManagedOrAbove) {
  name: 'alert-vpngw-tunnel-down-p1-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    description: 'VPN tunnel offline no redundant tunnel P1'
    severity: 0
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [targetResourceGroupId]
    targetResourceType: 'Microsoft.Network/virtualNetworkGateways'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'tunnel-down'
          metricName: 'TunnelConnectionCount'
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Total'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroupP1Id }
    ]
  }
}

// ── 8. VPN Gateway – tunnel offline, redundant active (P2) ───
resource alertVpnTunnelDownP2 'Microsoft.Insights/metricAlerts@2018-03-01' = if (isManagedOrAbove) {
  name: 'alert-vpngw-tunnel-down-p2-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    description: 'VPN tunnel offline redundant tunnel active P2'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [targetResourceGroupId]
    targetResourceType: 'Microsoft.Network/virtualNetworkGateways'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'tunnel-partial-down'
          metricName: 'TunnelConnectionCount'
          operator: 'LessThan'
          threshold: 2
          timeAggregation: 'Total'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroupP2Id }
    ]
  }
}

// ── 9. VPN Gateway – bandwidth > 80% SKU limit (P3, dynamic) ─
resource alertVpnBandwidth 'Microsoft.Insights/metricAlerts@2018-03-01' = if (isManagedOrAbove) {
  name: 'alert-vpngw-bandwidth-p3-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    description: 'VPN Gateway bandwidth high P3 dynamic threshold'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    scopes: [targetResourceGroupId]
    targetResourceType: 'Microsoft.Network/virtualNetworkGateways'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
#disable-next-line BCP037 BCP035
          criterionType: 'DynamicThresholdCriterion'
          name: 'gateway-bandwidth'
          metricName: 'AverageBandwidth'
          operator: 'GreaterThan'
          alertSensitivity: 'Medium'
          failingPeriods: {
            numberOfEvaluationPeriods: 3
            minFailingPeriodsToAlert: 2
          }
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroupP3Id }
    ]
  }
}

// ── 10. AVD – session hosts unavailable (P1) ──────────────────
resource alertAvdHostsDown 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (isAdvanced) {
  name: 'alert-avd-hosts-unavailable-p1-${klantCode}'
  location: location
  tags: tags
  properties: {
    displayName: '[${klantCode}] AVD session hosts unavailable (P1)'
    description: 'Fires when more than 2 session hosts or > 25% of pool are unavailable.'
    severity: 0
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            WVDErrors
            | where TimeGenerated > ago(5m)
            | where ServiceError == "true"
            | summarize HostErrors = dcount(SessionHostName)
            | where HostErrors > 2
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupP1Id]
    }
  }
}

// ── 11. AVD – login/connection errors dynamic (P2) ────────────
resource alertAvdConnectionErrors 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (isAdvanced) {
  name: 'alert-avd-connection-errors-p2-${klantCode}'
  location: location
  tags: tags
  properties: {
    displayName: '[${klantCode}] AVD connection errors elevated (P2, dynamic)'
    description: 'Fires when AVD connection errors exceed the dynamically learned baseline.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            WVDConnections
            | where TimeGenerated > ago(15m)
            | where State == "Connected"
            | summarize Errors = countif(isnotempty(ClientSideIPAddress) == false)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 5
          failingPeriods: {
            numberOfEvaluationPeriods: 2
            minFailingPeriodsToAlert: 2
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupP2Id]
    }
  }
}

// ── 12. AVD scaling plan autoscale failed (P2) ────────────────
resource alertAvdScalingFailed 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (isAdvanced) {
  name: 'alert-avd-scaling-failed-p2-${klantCode}'
  location: location
  tags: tags
  properties: {
    displayName: '[${klantCode}] AVD autoscale action failed (P2)'
    description: 'Fires when the AVD scaling plan fails to execute an autoscale action.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            WVDErrors
            | where Source == "ScalingPlan"
            | where ServiceError == "true"
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupP2Id]
    }
  }
}

// ── 13. Storage availability < 99.9% (P1) ────────────────────
resource alertStorageAvailability 'Microsoft.Insights/metricAlerts@2018-03-01' = if (isManagedOrAbove) {
  name: 'alert-storage-availability-p1-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Storage account availability below 99.9 percent over 5 minutes P1'
    severity: 0
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [targetResourceGroupId]
    targetResourceType: 'Microsoft.Storage/storageAccounts'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'storage-availability'
          metricName: 'Availability'
          operator: 'LessThan'
          threshold: json('99.9')
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroupP1Id }
    ]
  }
}

// ── 14. Storage capacity > 80% (P3) ─────────────────────────
resource alertStorageCapacityP3 'Microsoft.Insights/metricAlerts@2018-03-01' = if (isManagedOrAbove) {
  name: 'alert-storage-capacity-80-p3-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Storage used capacity exceeds 80 percent of provisioned limit P3'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    scopes: [targetResourceGroupId]
    targetResourceType: 'Microsoft.Storage/storageAccounts'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'storage-capacity-80'
          metricName: 'UsedCapacity'
          operator: 'GreaterThan'
          // 80% of 100 TB = 87960930222080 bytes; adjust per customer in parameter file
          threshold: 87960930222080
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroupP3Id }
    ]
  }
}

// ── 15. Storage capacity > 95% (P2) ─────────────────────────
resource alertStorageCapacityP2 'Microsoft.Insights/metricAlerts@2018-03-01' = if (isManagedOrAbove) {
  name: 'alert-storage-capacity-95-p2-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Storage used capacity exceeds 95 percent of provisioned limit P2'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    scopes: [targetResourceGroupId]
    targetResourceType: 'Microsoft.Storage/storageAccounts'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'storage-capacity-95'
          metricName: 'UsedCapacity'
          operator: 'GreaterThan'
          // 95% of 100 TB = 104549375664701 bytes; adjust per customer
          threshold: 104549375664701
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroupP2Id }
    ]
  }
}

// ── 16. Azure Files – transaction throttling > 10 min (P2) ──
resource alertAzureFilesThrottling 'Microsoft.Insights/metricAlerts@2018-03-01' = if (isAdvanced) {
  name: 'alert-azurefiles-throttling-p2-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Azure Files SuccessWithThrottling sustained more than 10 minutes P2'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    scopes: [targetResourceGroupId]
    targetResourceType: 'Microsoft.Storage/storageAccounts/fileServices'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'files-throttling'
          metricName: 'Transactions'
          dimensions: [
            {
              name: 'ResponseType'
              operator: 'Include'
              values: ['SuccessWithThrottling']
            }
          ]
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Total'
        }
      ]
    }
    actions: [
      { actionGroupId: actionGroupP2Id }
    ]
  }
}

// ── 17. VM availability – heartbeat lost > 5 min (P1) ────────
// Combined Resource Health + Heartbeat metric alert
resource alertVmHeartbeat 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = if (isManagedOrAbove) {
  name: 'alert-vm-heartbeat-p1-${klantCode}'
  location: location
  tags: tags
  properties: {
    displayName: '[${klantCode}] VM heartbeat lost > 5 min (P1)'
    description: 'Fires when a VM stops sending heartbeat signals for more than 5 minutes.'
    severity: 0
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            Heartbeat
            | summarize LastHeartbeat = max(TimeGenerated) by Computer
            | where LastHeartbeat < ago(5m)
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupP1Id]
    }
  }
}

// ── 18. Activity Log – critical resource deleted/changed (P1) ─
resource alertCriticalResourceChange 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alert-activity-critical-change-p1-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [subscription().id]
    condition: {
      allOf: [
        { field: 'category', equals: 'Administrative' }
        { field: 'operationName', containsAny: [
          'Microsoft.Network/networkSecurityGroups/delete'
          'Microsoft.Network/virtualNetworks/delete'
          'Microsoft.RecoveryServices/vaults/delete'
          'Microsoft.Compute/virtualMachines/delete'
          'Microsoft.Network/virtualNetworkGateways/delete'
        ]}
        { field: 'status', equals: 'Succeeded' }
      ]
    }
    actions: {
      actionGroups: [
        { actionGroupId: actionGroupP1Id }
      ]
    }
    description: 'Fires when a critical resource (NSG, VNet, Vault, VM, VPN GW) is deleted.'
  }
}

// ── 19. Activity Log – RBAC change at subscription level (P2) ─
resource alertRbacChange 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'alert-activity-rbac-change-p2-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    scopes: [subscription().id]
    condition: {
      allOf: [
        { field: 'category', equals: 'Administrative' }
        { field: 'operationName', containsAny: [
          'Microsoft.Authorization/roleAssignments/write'
          'Microsoft.Authorization/roleAssignments/delete'
          'Microsoft.Authorization/roleDefinitions/write'
          'Microsoft.Authorization/roleDefinitions/delete'
        ]}
        { field: 'status', equals: 'Succeeded' }
      ]
    }
    actions: {
      actionGroups: [
        { actionGroupId: actionGroupP2Id }
      ]
    }
    description: 'Fires when any RBAC role assignment or definition is created or deleted at subscription level.'
  }
}

// ── 20. Azure Policy – non-compliant resource detected (P3/P2) ─
resource alertPolicyNonCompliant 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-policy-noncompliant-p3-${klantCode}'
  location: location
  tags: tags
  properties: {
    displayName: '[${klantCode}] New non-compliant resource detected (P3)'
    description: 'Fires when Azure Policy detects a new non-compliant resource in the baseline policy set. Escalate to P2 for security category policies.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    scopes: [workspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            AzureActivity
            | where CategoryValue == "Policy"
            | where ActivityStatusValue == "Start"
            | where Properties has "NonCompliant"
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [actionGroupP3Id]
    }
  }
}
