// ============================================================
// Module: autotask-logicapp.bicep
// Purpose: Deploy a Logic App (Consumption) with HTTP trigger
//          that receives Azure Monitor common alert schema
//          payloads. Phase 1: logs payload to workspace only.
//          Phase 2 (TODO): add Autotask API call for ticket
//          creation using the queue mapping below.
//
// Autotask queue mapping (TO section 6 – open item 2):
//   P1 → Queue: <TBD P1 queue name>   Team: <TBD>
//   P2 → Queue: <TBD P2 queue name>   Team: <TBD>
//   P3 → Queue: Reporting             Team: <TBD>
// Fill in queue/team names when decided, then add the
// Autotask API action below the deduplication comment.
//
// Deduplication (Phase 2 note):
//   deduplicationWindowMinutes = 5
//   Implement as a Logic App stateful workflow with a condition
//   checking a Cosmos DB / Storage Table for recent alert IDs.
// Chore: 6
// ============================================================

@description('Azure region for deployment. Must be westeurope.')
@allowed(['westeurope'])
param location string

@description('Full resource ID of the Log Analytics Workspace (reserved for Phase 2 direct query).')
#disable-next-line no-unused-params
param workspaceId string

@description('Workspace Customer ID (GUID) for Data Collector API.')
param workspaceCustomerId string

@description('Resource tags to apply.')
param tags object = {}

@description('Customer identifier code.')
param klantCode string

// ── Logic App (Consumption) ───────────────────────────────────
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'logic-autotask-monitoring-weu'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        workspaceId: {
          type: 'string'
          defaultValue: workspaceCustomerId
        }
      }
      triggers: {
        http_trigger: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {} // Accept any payload; Azure Monitor uses Common Alert Schema
          }
        }
      }
      actions: {
        // ── Phase 1: Parse and log the alert payload ──────────
        Parse_Alert_Payload: {
          type: 'ParseJson'
          inputs: {
            content: '@triggerBody()'
            schema: {
              type: 'object'
              properties: {
                data: {
                  type: 'object'
                  properties: {
                    essentials: {
                      type: 'object'
                      properties: {
                        severity: { type: 'string' }
                        alertTargetIDs: {
                          type: 'array'
                          items: { type: 'string' }
                        }
                        alertRule: { type: 'string' }
                        firedDateTime: { type: 'string' }
                      }
                    }
                  }
                }
              }
            }
          }
          runAfter: {}
        }

        // Log full payload to Log Analytics via HTTP Data Collector API
        Log_To_Workspace: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: 'https://api.loganalytics.io/v1/workspaces/@{parameters(\'workspaceId\')}/query'
            // NOTE: In a real deployment, use the Log Analytics Data Collector API:
            // POST https://<workspaceId>.ods.opinsights.azure.com/api/logs?api-version=2016-04-01
            // With header Log-Type: AlertPayloadLog
            // Authentication: use Managed Identity with Log Analytics Contributor role
            body: '@triggerBody()'
          }
          runAfter: {
            Parse_Alert_Payload: ['Succeeded']
          }
        }

        // ── Phase 2 placeholder: Autotask ticket creation ─────
        // TODO: Replace this comment block with:
        // 1. Condition: check severity from Parse_Alert_Payload
        // 2. Switch on severity (P1 / P2 / P3)
        // 3. HTTP POST to Autotask API:
        //    POST https://webservices<zone>.autotask.net/ATServicesRest/v1.0/Tickets
        //    Headers: ApiIntegrationCode, UserName, Secret
        //    Body: { queueID: <queue GUID>, title: alertRule, description: full payload }
        // 4. deduplicationWindowMinutes = 5 (check Storage Table for recent alertRule+target)
        // ──────────────────────────────────────────────────────

        Return_200: {
          type: 'Response'
          inputs: {
            statusCode: 200
            body: {
              status: 'logged'
              phase: 'Phase1-ObservationMode'
              klantCode: klantCode
            }
          }
          runAfter: {
            Log_To_Workspace: ['Succeeded', 'Failed']
          }
        }
      }
      outputs: {}
    }
  }
}

// ── Outputs ───────────────────────────────────────────────────
@description('HTTPS trigger URL for the Logic App. Pass this to action-groups.bicep.')
@sys.secure()
output logicAppWebhookUri string = listCallbackUrl(
  '${logicApp.id}/triggers/http_trigger',
  '2019-05-01'
).value

@description('Resource ID of the Logic App.')
output logicAppId string = logicApp.id
