// ============================================================
// Mock resources for pilot testing (Chore 2)
// Resource group: rg-pilot-mock-weu
// Purpose: Representative Azure resources that produce the
//          signals the monitoring baseline alert rules target.
//
// Cost note: Deallocate VM and AVD session host when not testing.
//            VPN Gateway (Basic) bills by the hour – delete when
//            not needed for extended periods.
// VPN Gateway SKU note: Basic SKU is used here instead of VpnGw1.
//   Basic does not support IKEv2 or BGP. Production environments
//   use IKEv2 (from existing Bicep audit). For mock purposes only
//   tunnel metrics and connectivity signals are needed, not VPN
//   configuration parity. See docs/mock-environment.md.
// ============================================================

@allowed(['westeurope'])
param location string = 'westeurope'
param klantCode string = 'pilot'

@description('Admin username for the mock VM.')
param adminUsername string = 'azureadmin'

@description('Admin password for the mock VM. Provide via parameter file or Key Vault reference.')
@secure()
param adminPassword string

@description('Token expiration time for AVD host pool registration (ISO 8601). Defaults to 24h from deployment time.')
param avdTokenExpiry string = dateTimeAdd(utcNow(), 'P1D')

var tags = {
  Environment: 'mock'
  ManagedBy: 'platform-team'
  CostCenter: 'monitoring-pilot'
}

var prefix = '${klantCode}-mock-weu'

// ── Virtual Network ───────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'vnet-${prefix}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.10.0.0/16']
    }
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: '10.10.0.0/27'
        }
      }
      {
        name: 'snet-workloads'
        properties: {
          addressPrefix: '10.10.1.0/24'
        }
      }
    ]
  }
}

// ── Recovery Services Vault ───────────────────────────────────
resource rsv 'Microsoft.RecoveryServices/vaults@2024-04-01' = {
  name: 'rsv-${prefix}'
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    securitySettings: {
      softDeleteSettings: {
        softDeleteState: 'Enabled'
        softDeleteRetentionPeriodInDays: 14
      }
      immutabilitySettings: {
        state: 'Disabled'
      }
    }
  }
}

// Default backup policy (daily, 30-day retention)
resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2024-04-01' = {
  parent: rsv
  name: 'DefaultPolicy'
  properties: {
    backupManagementType: 'AzureIaasVM'
    instantRpRetentionRangeInDays: 2
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: ['2000-01-01T02:00:00Z']
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: ['2000-01-01T02:00:00Z']
        retentionDuration: {
          count: 30
          durationType: 'Days'
        }
      }
    }
    timeZone: 'UTC'
  }
}

// ── Storage Account + Azure Files (FSLogix share) ─────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: 'st${replace(klantCode, '-', '')}mockweu'
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    largeFileSharesState: 'Enabled'
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    // SMB Multichannel not supported on Visual Studio subscriptions
    protocolSettings: {
      smb: {}
    }
  }
}

resource fslogixShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: fileService
  name: 'fslogix'
  properties: {
    accessTier: 'TransactionOptimized'
    shareQuota: 100 // GB
  }
}

// ── Network Interface for VM ──────────────────────────────────
resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: 'nic-vm-${prefix}-001'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: vnet.properties.subnets[1].id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// ── Windows Server VM (B2s, standalone for mock) ─────────────
resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: 'vm-${prefix}-001'
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-datacenter-g2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        deleteOption: 'Delete'
      }
    }
    osProfile: {
      computerName: 'vm-mock-001'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        patchSettings: {
          patchMode: 'AutomaticByOS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: { deleteOption: 'Delete' }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// Backup the mock VM to the RSV
resource vmBackupProtection 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2024-04-01' = {
  name: '${rsv.name}/Azure/iaasvmcontainer;iaasvmcontainerv2;${resourceGroup().name};${vm.name}/vm;iaasvmcontainerv2;${resourceGroup().name};${vm.name}'
  location: location
  tags: tags
  properties: {
    protectedItemType: 'Microsoft.Compute/virtualMachines'
    policyId: backupPolicy.id
    sourceResourceId: vm.id
  }
}

// ── Public IP for VPN Gateway ─────────────────────────────────
resource vpnPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: 'pip-vgw-${prefix}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ── VPN Gateway (Basic SKU – mock only, see SKU note above) ──
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-01-01' = {
  name: 'vgw-${prefix}-001'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'gwipconfig'
        properties: {
          subnet: {
            id: vnet.properties.subnets[0].id
          }
          publicIPAddress: {
            id: vpnPublicIp.id
          }
        }
      }
    ]
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    sku: {
      name: 'Basic'
      tier: 'Basic'
    }
    enableBgp: false
  }
}

// ── AVD Host Pool ─────────────────────────────────────────────
// NOTE: If AVD quota is unavailable in West Europe, this resource
//       will fail deployment. Document the gap and remove this block.
//       AVD alert rules (rules 10-12) remain in alert-rules.bicep.
resource hostPool 'Microsoft.DesktopVirtualization/hostPools@2024-04-03' = {
  name: 'vdpool-${prefix}-001'
  location: location
  tags: tags
  properties: {
    hostPoolType: 'Pooled'
    loadBalancerType: 'BreadthFirst'
    preferredAppGroupType: 'Desktop'
    maxSessionLimit: 10
    validationEnvironment: true
    registrationInfo: {
      expirationTime: avdTokenExpiry
      registrationTokenOperation: 'Update'
    }
  }
}

// ── Outputs ──────────────────────────────────────────────────
output rsvId string = rsv.id
output storageAccountId string = storageAccount.id
output vmId string = vm.id
output vpnGatewayId string = vpnGateway.id
output hostPoolId string = hostPool.id
output vnetId string = vnet.id
