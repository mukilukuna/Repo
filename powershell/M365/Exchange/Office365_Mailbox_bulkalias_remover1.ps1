<# Compatibiliteitsnaam: gebruikt de centrale aliasbeheerfunctie in Manage-MailboxAliases.ps1. #>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory)][string]$Domain,
    [switch]$Apply
)

$CentralScript = Join-Path $PSScriptRoot 'Manage-MailboxAliases.ps1'
$Arguments = @{ Action = 'RemoveDomain'; Domain = $Domain }
if ($Apply) { $Arguments.Apply = $true }
if ($WhatIfPreference) { $Arguments.WhatIf = $true }
& $CentralScript @Arguments
