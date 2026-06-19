// ============================================================
// Module: policy.bicep
// Purpose: Assign built-in DeployIfNotExists (DINE) Azure Policy
//          definitions to enforce diagnostic settings on all
//          baseline resource types in the monitored resource group.
//
// Deployment scope: this module MUST be deployed targeting the
// monitored resource group (not the monitoring RG). In
// monitoring.bicep it is called with:
//   scope: resourceGroup(monitoredSubId, monitoredRgName)
//
// Note: PolicySetDefinitions require subscription/MG scope and
//       cannot be created at resource group scope. Individual
//       policy assignments at RG scope are used instead.
// Chore: 8
// ============================================================

@description('Customer identifier code.')
param klantCode string

@description('Full resource ID of the Log Analytics Workspace.')
param workspaceId string

@description('Azure region for the policy assignment managed identity. Must be westeurope.')
@allowed(['westeurope'])
param location string

// ── Built-in DINE policy definition IDs (AzureCloud) ─────────
// These IDs are stable built-in definitions; verify in Portal if
// subscription type differs (AzureGov, AzureChina have different IDs).
var policyVm = '/providers/Microsoft.Authorization/policyDefinitions/0868462e-8a38-4f8d-ae35-2e02b6f6d5c7'
var policyStorage = '/providers/Microsoft.Authorization/policyDefinitions/59759c62-9a22-4cdf-ae64-074495983fef'
var policyRsv = '/providers/Microsoft.Authorization/policyDefinitions/c717fb0c-d118-4c43-ab3d-ece30ac81fb3'
var policyVpnGw = '/providers/Microsoft.Authorization/policyDefinitions/ed6ae75a-828f-4fea-88fd-dead1145f1dd'

// ── Policy Assignment: VM diagnostic settings ────────────────
resource assignmentVm 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'pa-diag-vm-${klantCode}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: '[${klantCode}] Diag settings – VMs to LAW'
    policyDefinitionId: policyVm
    parameters: {
      logAnalytics: { value: workspaceId }
    }
    enforcementMode: 'Default'
    nonComplianceMessages: [
      {
        message: 'VM diagnostic settings must route to the monitoring Log Analytics Workspace.'
      }
    ]
  }
}

// ── Policy Assignment: Storage Account diagnostic settings ────
resource assignmentStorage 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'pa-diag-storage-${klantCode}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: '[${klantCode}] Diag settings – Storage to LAW'
    policyDefinitionId: policyStorage
    parameters: {
      logAnalytics: { value: workspaceId }
    }
    enforcementMode: 'Default'
    nonComplianceMessages: [
      {
        message: 'Storage account diagnostic settings must route to the monitoring Log Analytics Workspace.'
      }
    ]
  }
}

// ── Policy Assignment: Recovery Services Vault ────────────────
resource assignmentRsv 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'pa-diag-rsv-${klantCode}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: '[${klantCode}] Diag settings – RSV to LAW'
    policyDefinitionId: policyRsv
    parameters: {
      logAnalytics: { value: workspaceId }
    }
    enforcementMode: 'Default'
    nonComplianceMessages: [
      {
        message: 'Recovery Services Vault diagnostic settings must route to the monitoring Log Analytics Workspace.'
      }
    ]
  }
}

// ── Policy Assignment: VPN Gateway ────────────────────────────
resource assignmentVpnGw 'Microsoft.Authorization/policyAssignments@2023-04-01' = {
  name: 'pa-diag-vpngw-${klantCode}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: '[${klantCode}] Diag settings – VPN GW to LAW'
    policyDefinitionId: policyVpnGw
    parameters: {
      logAnalytics: { value: workspaceId }
    }
    enforcementMode: 'Default'
    nonComplianceMessages: [
      {
        message: 'VPN Gateway diagnostic settings must route to the monitoring Log Analytics Workspace.'
      }
    ]
  }
}

// ── Role: Contributor on this RG for each assignment's MI ─────
// Each policy assignment's managed identity needs Contributor rights
// to deploy diagnostic settings on resources in this RG (DINE effect).

resource roleVm 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(assignmentVm.id, 'Contributor', resourceGroup().id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: assignmentVm.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(assignmentStorage.id, 'Contributor', resourceGroup().id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: assignmentStorage.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleRsv 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(assignmentRsv.id, 'Contributor', resourceGroup().id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: assignmentRsv.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource roleVpnGw 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(assignmentVpnGw.id, 'Contributor', resourceGroup().id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: assignmentVpnGw.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Outputs ───────────────────────────────────────────────────
@description('Resource ID of the VM policy assignment.')
output policyAssignmentVmId string = assignmentVm.id

@description('Resource ID of the Storage policy assignment.')
output policyAssignmentStorageId string = assignmentStorage.id
