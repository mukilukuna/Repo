// ============================================================
// Module: data-collection-rules.bicep
// Purpose: Deploy Data Collection Rules (DCRs) per resource type
//          and tier, routing diagnostics to the Log Analytics
//          Workspace created in log-analytics.bicep.
// Chore: 4
// ============================================================

@description('Full resource ID of the Log Analytics Workspace.')
param workspaceId string

@description('Deployment tier. Determines which DCRs are deployed.')
@allowed(['Essential', 'Managed', 'Advanced'])
param tier string

@description('Azure region for deployment. Must be westeurope.')
@allowed(['westeurope'])
param location string

@description('Resource tags to apply.')
param tags object = {}

// Managed or Advanced tier is needed for DCRs beyond Activity Log
var isManagedOrAbove = tier != 'Essential'

// ── VM: Performance counters + Windows Event Log ──────────────
resource dcrVm 'Microsoft.Insights/dataCollectionRules@2023-03-11' = if (isManagedOrAbove) {
  name: 'dcr-vm-managed-weu'
  location: location
  tags: tags
  properties: {
    description: 'Collect VM performance counters and Windows Event Logs.'
    dataSources: {
      performanceCounters: [
        {
          name: 'VMInsightsPerf'
          streams: ['Microsoft-InsightsMetrics']
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor Information(_Total)\\% Processor Time'
            '\\Memory\\Available Bytes'
            '\\LogicalDisk(_Total)\\% Disk Time'
            '\\LogicalDisk(_Total)\\Disk Reads/sec'
            '\\LogicalDisk(_Total)\\Disk Writes/sec'
            '\\Network Interface(*)\\Bytes Total/sec'
          ]
        }
      ]
      windowsEventLogs: [
        {
          name: 'WindowsEventLogs'
          streams: ['Microsoft-Event']
          xPathQueries: [
            'Application!*[System[(Level=1 or Level=2 or Level=3)]]'
            'System!*[System[(Level=1 or Level=2 or Level=3)]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'workspace'
          workspaceResourceId: workspaceId
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-InsightsMetrics']
        destinations: ['workspace']
      }
      {
        streams: ['Microsoft-Event']
        destinations: ['workspace']
      }
    ]
  }
}

// ── Outputs (DCR IDs used by policy.bicep) ────────────────────
@description('Resource ID of the VM DCR.')
output dcrVmId string = isManagedOrAbove ? dcrVm.id : ''

// Storage, RSV, VPN GW and AVD use Diagnostic Settings (via Policy),
// not agent-based DCRs. Return empty strings for backward compat.
@description('Resource ID of the Storage DCR (N/A – uses Diagnostic Settings).')
output dcrStorageId string = ''

@description('Resource ID of the RSV DCR (N/A – uses Diagnostic Settings).')
output dcrRsvId string = ''

@description('Resource ID of the VPN Gateway DCR (N/A – uses Diagnostic Settings).')
output dcrVpnId string = ''

@description('Resource ID of the AVD DCR (N/A – session hosts use VM DCR).')
output dcrAvdId string = ''
