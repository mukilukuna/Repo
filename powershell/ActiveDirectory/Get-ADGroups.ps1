<# Compatibiliteitswrapper voor Get-ADInventory.ps1 -ObjectType Groups. #>
[CmdletBinding()]
param (
    [string[]]$SearchBase,
    [ValidateSet('include', 'exclude')][string]$Builtin = 'exclude',
    [string]$CSVPath
)

$CentralScript = Join-Path $PSScriptRoot 'Get-ADInventory.ps1'
$Arguments = @{ ObjectType = 'Groups'; Builtin = $Builtin }
if ($SearchBase) { $Arguments.SearchBase = $SearchBase }
if (-not [string]::IsNullOrWhiteSpace($CSVPath)) { $Arguments.CSVPath = $CSVPath }
& $CentralScript @Arguments
