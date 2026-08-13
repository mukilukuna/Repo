<#
.SYNOPSIS
    Compatibiliteitswrapper voor Add-UsersToGroup.ps1 -Mode PerRow.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$Path,

    [char]$Delimiter = ',',

    [ValidateSet('DisplayName', 'Email', 'UserPrincipalName')]
    [string]$Filter = 'DisplayName',

    [string]$UserColumn = 'User',

    [string]$GroupColumn = 'Group'
)

$CentralScript = Join-Path $PSScriptRoot 'Add-UsersToGroup.ps1'
$Arguments = @{
    Mode        = 'PerRow'
    Path        = $Path
    Delimiter   = $Delimiter
    Filter      = $Filter
    UserColumn  = $UserColumn
    GroupColumn = $GroupColumn
}
if ($WhatIfPreference) {
    $Arguments.WhatIf = $true
}

& $CentralScript @Arguments
