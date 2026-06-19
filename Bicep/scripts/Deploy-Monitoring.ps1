#Requires -Version 7.0
<#
.SYNOPSIS
    Deploy the IT Synergy monitoring baseline for a customer.

.DESCRIPTION
    Builds, validates (what-if), and optionally deploys the monitoring.bicep
    module for the specified customer. Always runs `az bicep build` and
    `az deployment group what-if` before a real deployment.

    Run with -WhatIf to validate only (nothing is deployed).

.PARAMETER KlantCode
    Customer identifier (matches folder name under infra/customers/).

.PARAMETER ResourceGroup
    Target resource group for the monitoring baseline (rg-<klantCode>-platform-weu).

.PARAMETER SubscriptionId
    Azure subscription ID where the monitoring baseline is deployed.

.PARAMETER Location
    Azure region (default: westeurope).

.PARAMETER WhatIf
    When specified, validates and shows what-if output only. No resources are deployed.

.EXAMPLE
    .\Deploy-Monitoring.ps1 -KlantCode pilot -ResourceGroup rg-pilot-platform-weu `
        -SubscriptionId 098e34b6-d88e-447e-ba9a-245275343d63 -WhatIf

.EXAMPLE
    .\Deploy-Monitoring.ps1 -KlantCode pilot -ResourceGroup rg-pilot-platform-weu `
        -SubscriptionId 098e34b6-d88e-447e-ba9a-245275343d63
#>
param(
    [Parameter(Mandatory)]
    [string]$KlantCode,

    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [string]$Location = 'westeurope',

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Support both direct az and the full path used in VS Code terminals
$az = if (Get-Command az -ErrorAction SilentlyContinue) { 'az' } else { 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd' }

$repoRoot  = Split-Path -Parent $PSScriptRoot
$template  = Join-Path $repoRoot "infra/platform/modules/monitoring/monitoring.bicep"
$paramFile = Join-Path $repoRoot "infra/customers/$KlantCode/monitoring.bicepparam"

# ── Validate inputs ───────────────────────────────────────────
if (-not (Test-Path $template)) {
    throw "Template not found: $template"
}
if (-not (Test-Path $paramFile)) {
    throw "Parameter file not found: $paramFile — create infra/customers/$KlantCode/monitoring.bicepparam first."
}

Write-Host "`n=== Monitoring Baseline Deployment ===" -ForegroundColor Cyan
Write-Host "Customer   : $KlantCode"
Write-Host "Subscription: $SubscriptionId"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Location   : $Location"
Write-Host "Mode       : $(if ($WhatIf) { 'What-If (no deployment)' } else { 'DEPLOY' })`n"

# ── Step 1: Set subscription ─────────────────────────────────
Write-Host "--- Step 1: Setting subscription context ---" -ForegroundColor Yellow
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) { throw "Failed to set subscription." }

# ── Step 2: Build (lint/compile check) ──────────────────────
Write-Host "`n--- Step 2: Building Bicep (lint/compile) ---" -ForegroundColor Yellow
az bicep build --file $template
if ($LASTEXITCODE -ne 0) { throw "Bicep build failed. Fix errors before deploying." }
Write-Host "Bicep build clean." -ForegroundColor Green

# ── Step 3: Ensure resource group exists ─────────────────────
Write-Host "`n--- Step 3: Ensuring resource group exists ---" -ForegroundColor Yellow
$rgExists = az group show --name $ResourceGroup --subscription $SubscriptionId 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $rgExists) {
    if ($WhatIf) {
        Write-Host "Resource group $ResourceGroup does not exist. Would be created on real deploy." -ForegroundColor Cyan
    } else {
        Write-Host "Creating resource group $ResourceGroup in $Location..."
        az group create --name $ResourceGroup --location $Location `
            --tags Environment=monitoring ManagedBy=platform-team KlantCode=$KlantCode 'baseline-version=0.1-pilot'
        if ($LASTEXITCODE -ne 0) { throw "Failed to create resource group." }
    }
} else {
    Write-Host "Resource group $ResourceGroup already exists."
}

# ── Step 4: What-If ──────────────────────────────────────────
Write-Host "`n--- Step 4: Running what-if preflight ---" -ForegroundColor Yellow
az deployment group what-if `
    --resource-group $ResourceGroup `
    --template-file  $template `
    --parameters     $paramFile `
    --no-pretty-print

if ($LASTEXITCODE -ne 0) { throw "What-if failed. Review errors before proceeding." }

# ── Step 5: Deploy (only when -WhatIf is absent) ─────────────
if (-not $WhatIf) {
    Write-Host "`n--- Step 5: Deploying ---" -ForegroundColor Yellow
    $deploymentName = "monitoring-$KlantCode-$(Get-Date -Format 'yyyyMMdd-HHmm')"

    az deployment group create `
        --name           $deploymentName `
        --resource-group $ResourceGroup `
        --template-file  $template `
        --parameters     $paramFile

    if ($LASTEXITCODE -ne 0) { throw "Deployment failed." }

    Write-Host "`nDeployment '$deploymentName' completed successfully." -ForegroundColor Green
    Write-Host "Run 'az resource list -g $ResourceGroup --output table' to verify resources."
} else {
    Write-Host "`nWhat-If complete. No resources were deployed." -ForegroundColor Cyan
    Write-Host "Re-run without -WhatIf to deploy."
}
