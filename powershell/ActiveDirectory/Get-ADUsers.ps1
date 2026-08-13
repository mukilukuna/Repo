<# Compatibiliteitswrapper voor Get-ADInventory.ps1 -ObjectType Users. #>
[CmdletBinding()]
param (
    [bool]$GetManager = $true,
    [string[]]$SearchBase,
    [ValidateSet('true', 'false', 'both')][string]$Enabled = 'true',
    [string]$CSVPath
)

$CentralScript = Join-Path $PSScriptRoot 'Get-ADInventory.ps1'
$Arguments = @{
    ObjectType  = 'Users'
    GetManager = $GetManager
    Enabled     = $Enabled
}
if ($SearchBase) { $Arguments.SearchBase = $SearchBase }
if (-not [string]::IsNullOrWhiteSpace($CSVPath)) { $Arguments.CSVPath = $CSVPath }
& $CentralScript @Arguments
