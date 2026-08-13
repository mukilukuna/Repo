<# Compatibiliteitswrapper voor Get-ADInventory.ps1 -ObjectType Computers. #>
[CmdletBinding()]
param (
    [string[]]$SearchBase,
    [ValidateSet('true', 'false', 'both')][string]$Enabled = 'true',
    [string]$CSVPath
)

$CentralScript = Join-Path $PSScriptRoot 'Get-ADInventory.ps1'
$Arguments = @{ ObjectType = 'Computers'; Enabled = $Enabled }
if ($SearchBase) { $Arguments.SearchBase = $SearchBase }
if (-not [string]::IsNullOrWhiteSpace($CSVPath)) { $Arguments.CSVPath = $CSVPath }
& $CentralScript @Arguments
