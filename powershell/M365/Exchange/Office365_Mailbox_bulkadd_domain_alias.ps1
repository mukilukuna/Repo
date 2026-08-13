[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory)][string[]]$SourceDomain,
    [Parameter(Mandatory)][string]$TargetDomain,
    [switch]$Apply
)

$CentralScript = Join-Path $PSScriptRoot 'Manage-MailboxAliases.ps1'
$Arguments = @{ Action = 'AddDomain'; SourceDomain = $SourceDomain; TargetDomain = $TargetDomain }
if ($Apply) { $Arguments.Apply = $true }
if ($WhatIfPreference) { $Arguments.WhatIf = $true }
& $CentralScript @Arguments
