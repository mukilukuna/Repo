#Requires -Version 7.0
<#
.SYNOPSIS
    Deploy mock resources for the monitoring baseline pilot (Chore 2).

.DESCRIPTION
    Deploys rg-pilot-mock-weu with all representative Azure resources:
    Recovery Services Vault, Storage account + Azure Files share,
    Windows Server VM (B2s), VPN Gateway (Basic), and AVD host pool.

.PARAMETER SubscriptionId
    Azure subscription ID.

.PARAMETER Location
    Azure region (default: westeurope).

.PARAMETER AdminPassword
    Admin password for the mock VM. Prompted if not supplied.

.PARAMETER WhatIf
    Validates and shows what-if output only. No resources are deployed.

.EXAMPLE
    .\Deploy-MockResources.ps1 -SubscriptionId 098e34b6-d88e-447e-ba9a-245275343d63 -WhatIf
#>
param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [string]$Location = 'westeurope',

    [string]$ResourceGroup = 'rg-pilot-mock-weu',

    [Parameter(Mandatory)]
    [securestring]$AdminPassword,

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Support both direct az and the full path used in VS Code terminals
$az = if (Get-Command az -ErrorAction SilentlyContinue) { 'az' } else { 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd' }

$repoRoot  = Split-Path -Parent $PSScriptRoot
$template  = Join-Path $repoRoot "infra/mock/resources.bicep"

# Convert SecureString to plain text for az CLI (only in memory, not logged)
$adminPasswordPlain = [System.Net.NetworkCredential]::new('', $AdminPassword).Password

Write-Host "`n=== Mock Environment Deployment ===" -ForegroundColor Cyan
Write-Host "Subscription: $SubscriptionId"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Mode: $(if ($WhatIf) { 'What-If only' } else { 'DEPLOY' })`n"

& $az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Failed to set subscription." }

& $az bicep build --file $template
if ($LASTEXITCODE -ne 0) { throw "Bicep build failed." }

# Ensure resource group
$rgExists = & $az group show --name $ResourceGroup 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $rgExists) {
    if (-not $WhatIf) {
        & $az group create --name $ResourceGroup --location $Location `
            --tags Environment=mock ManagedBy=platform-team CostCenter=monitoring-pilot
    }
}

if ($WhatIf) {
    & $az deployment group what-if `
        --resource-group $ResourceGroup `
        --template-file  $template `
        --parameters adminPassword=$adminPasswordPlain
} else {
    & $az deployment group create `
        --name           "mock-resources-$(Get-Date -Format 'yyyyMMdd-HHmm')" `
        --resource-group $ResourceGroup `
        --template-file  $template `
        --parameters adminPassword=$adminPasswordPlain

    if ($LASTEXITCODE -ne 0) { throw "Deployment failed." }
    Write-Host "`nMock resources deployed to $ResourceGroup." -ForegroundColor Green
}

# Clear password from memory
$adminPasswordPlain = $null
