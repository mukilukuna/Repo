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
var isAdvanced = tier == 'Advanced'

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

// ── Storage account: capacity + transaction metrics ────────────
resource dcrStorage 'Microsoft.Insights/dataCollectionRules@2023-03-11' = if (isManagedOrAbove) {
  name: 'dcr-storage-managed-weu'
  location: location
  tags: tags
  properties: {
    description: 'Collect Storage account capacity and transaction metrics.'
    dataSources: {
      // Storage metrics are typically sent via Diagnostic Settings rather than DCR agents.
      // This DCR defines the destination; Policy (Chore 8) enforces the diagnostic setting.
      performanceCounters: []
    }
    destinations: {
      logAnalytics: [
        {
          name: 'workspace'
          workspaceResourceId: workspaceId
        }
      ]
    }
    dataFlows: []
  }
}

// ── Recovery Services Vault: AzureBackupReport ────────────────
resource dcrRsv 'Microsoft.Insights/dataCollectionRules@2023-03-11' = if (isManagedOrAbove) {
  name: 'dcr-rsv-managed-weu'
  location: location
  tags: tags
  properties: {
    description: 'Collect Recovery Services Vault backup diagnostic data (AzureBackupReport).'
    dataSources: {
      performanceCounters: []
    }
    destinations: {
      logAnalytics: [
        {
          name: 'workspace'
          workspaceResourceId: workspaceId
        }
      ]
    }
    dataFlows: []
  }
}

// ── VPN Gateway: GatewayDiagnosticLog + TunnelDiagnosticLog ──
resource dcrVpn 'Microsoft.Insights/dataCollectionRules@2023-03-11' = if (isManagedOrAbove) {
  name: 'dcr-vpngw-managed-weu'
  location: location
  tags: tags
  properties: {
    description: 'Collect VPN Gateway diagnostic logs (Gateway + Tunnel).'
    dataSources: {
      performanceCounters: []
    }
    destinations: {
      logAnalytics: [
        {
          name: 'workspace'
          workspaceResourceId: workspaceId
        }
      ]
    }
    dataFlows: []
  }
}

// ── AVD host pool: WVDConnections + WVDErrors + WVDHostRegistrations
resource dcrAvd 'Microsoft.Insights/dataCollectionRules@2023-03-11' = if (isAdvanced) {
  name: 'dcr-avd-advanced-weu'
  location: location
  tags: tags
  properties: {
    description: 'Collect AVD host pool diagnostic data (connections, errors, registrations).'
    dataSources: {
      performanceCounters: []
    }
    destinations: {
      logAnalytics: [
        {
          name: 'workspace'
          workspaceResourceId: workspaceId
        }
      ]
    }
    dataFlows: []
  }
}

// ── Outputs (DCR IDs used by policy.bicep) ────────────────────
@description('Resource ID of the VM DCR.')
output dcrVmId string = isManagedOrAbove ? dcrVm.id : ''

@description('Resource ID of the Storage DCR.')
output dcrStorageId string = isManagedOrAbove ? dcrStorage.id : ''

@description('Resource ID of the RSV DCR.')
output dcrRsvId string = isManagedOrAbove ? dcrRsv.id : ''

@description('Resource ID of the VPN Gateway DCR.')
output dcrVpnId string = isManagedOrAbove ? dcrVpn.id : ''

@description('Resource ID of the AVD DCR.')
output dcrAvdId string = isAdvanced ? dcrAvd.id : ''
