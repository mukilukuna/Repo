[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory)]
    [string]$AdminUrl,

    [ValidateSet('Disabled', 'Enabled')]
    [string]$State = 'Disabled'
)

$CentralScript = Join-Path $PSScriptRoot 'Set-SharePointTenantFeatures.ps1'
$Arguments = @{
    AdminUrl = $AdminUrl
    Setting  = 'TeamSiteSyncButton'
    State    = $State
}
if ($WhatIfPreference) {
    $Arguments.WhatIf = $true
}

& $CentralScript @Arguments
