[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory)][string]$Mailbox,
    [Parameter(Mandatory)][string]$Alias,
    [switch]$Apply
)

$CentralScript = Join-Path $PSScriptRoot 'Manage-MailboxAliases.ps1'
$Arguments = @{ Action = 'AddSingle'; Mailbox = $Mailbox; Alias = $Alias }
if ($Apply) { $Arguments.Apply = $true }
if ($WhatIfPreference) { $Arguments.WhatIf = $true }
& $CentralScript @Arguments
