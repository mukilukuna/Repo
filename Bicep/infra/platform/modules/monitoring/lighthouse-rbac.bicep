// ============================================================
// Module: lighthouse-rbac.bicep
// Purpose: Deploy Azure Lighthouse delegation template so
//          IT Synergy's managing tenant can access the customer
//          subscription for monitoring purposes, scoped to the
//          required roles only (Monitoring Reader/Contributor).
//
// NOTE (TO open item 3): The Entra group Object IDs below are
//       placeholder GUIDs. Fill in the actual group IDs when
//       the group names are decided. Deployment is blocked until
//       these IDs are provided. The Bicep compiles with any GUID.
// Chore: 9
// ============================================================

@description('Managing tenant ID (IT Synergy Azure AD tenant).')
param managingTenantId string

@description('Object ID of the Entra security group for Monitoring Reader access.')
param monitoringReaderGroupId string

@description('Object ID of the Entra security group for Monitoring Contributor access.')
param monitoringContributorGroupId string

@description('Customer identifier code.')
param klantCode string

// Lighthouse registration definition
resource registrationDefinition 'Microsoft.ManagedServices/registrationDefinitions@2022-10-01' = {
  name: guid('lighthouse-monitoring-${klantCode}')
  properties: {
    registrationDefinitionName: 'IT Synergy – Monitoring Baseline (${klantCode})'
    description: 'Delegates monitoring read and contribute access for the IT Synergy monitoring baseline.'
    managedByTenantId: managingTenantId
    authorizations: [
      // Monitoring Reader: view dashboards, alerts, Workbooks
      {
        principalId: monitoringReaderGroupId
        roleDefinitionId: '43d0d8ad-25c7-4714-9337-8ba259a9fe05' // Monitoring Reader
        principalIdDisplayName: 'IT Synergy – Monitoring Reader'
      }
      // Reader: enumerate resources for alert targeting (required by Monitoring Reader scope)
      {
        principalId: monitoringReaderGroupId
        roleDefinitionId: 'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
        principalIdDisplayName: 'IT Synergy – Resource Reader'
      }
      // Monitoring Contributor: manage alert rules, Action Groups, Workbooks
      {
        principalId: monitoringContributorGroupId
        roleDefinitionId: '749f88d5-cbae-40b8-bcfc-e573ddc772fa' // Monitoring Contributor
        principalIdDisplayName: 'IT Synergy – Monitoring Contributor'
      }
    ]
  }
}

// Apply the registration definition to the subscription
resource registrationAssignment 'Microsoft.ManagedServices/registrationAssignments@2022-10-01' = {
  name: guid('lighthouse-assignment-monitoring-${klantCode}')
  properties: {
    registrationDefinitionId: registrationDefinition.id
  }
}

// ── Outputs ──────────────────────────────────────────────────
@description('Resource ID of the Lighthouse registration definition.')
output registrationDefinitionId string = registrationDefinition.id

@description('Resource ID of the Lighthouse registration assignment.')
output registrationAssignmentId string = registrationAssignment.id
