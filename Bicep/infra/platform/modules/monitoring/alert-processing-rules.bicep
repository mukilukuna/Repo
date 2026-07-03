// ============================================================
// Module: alert-processing-rules.bicep
// Purpose: Deploy Alert Processing Rules (APR) that suppress all
//          alerts during the configurable maintenance window.
//          APRs are always deployed in the 'global' location.
// Chore: 5
// ============================================================

@description('Resource ID of the resource group to scope the suppression to.')
param targetResourceGroupId string

@description('Customer identifier code.')
param klantCode string

@description('Maintenance window start time (HH:mm:ss, UTC).')
param maintenanceWindowStart string = '02:00:00'

@description('Maintenance window end time (HH:mm:ss, UTC).')
param maintenanceWindowEnd string = '06:00:00'

@description('Day of week for the weekly maintenance window.')
@allowed(['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'])
param maintenanceWindowDayOfWeek string = 'Sunday'

@description('Resource tags to apply.')
param tags object = {}

// ── Alert Processing Rule – maintenance suppression ───────────
// APRs must always be deployed in the 'global' location.
resource apr 'Microsoft.AlertsManagement/actionRules@2021-08-08' = {
  name: 'apr-maintenance-${klantCode}'
  location: 'global'
  tags: tags
  properties: {
    description: 'Suppresses all alerts during the weekly maintenance window (${maintenanceWindowDayOfWeek} ${maintenanceWindowStart}‚${maintenanceWindowEnd} UTC).'
    scopes: [targetResourceGroupId]
    status: 'Enabled'
    schedule: {
      timeZone: 'UTC'
      recurrences: [
        {
          recurrenceType: 'Weekly'
          daysOfWeek: [maintenanceWindowDayOfWeek]
          startTime: maintenanceWindowStart
          endTime: maintenanceWindowEnd
        }
      ]
    }
    actions: [
      {
        actionType: 'RemoveAllActionGroups'
      }
    ]
  }
}

@description('Resource ID of the Alert Processing Rule.')
output aprId string = apr.id
