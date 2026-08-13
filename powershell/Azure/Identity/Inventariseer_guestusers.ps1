[CmdletBinding()]
param (
    [string]$ExportDirectory,

    [ValidateRange(1, 120)]
    [int]$InactiveMonths = 3
)

$CentralScript = Join-Path $PSScriptRoot 'Inventariseer_users.ps1'
$Arguments = @{
    ReportType     = 'InactiveGuests'
    InactiveMonths = $InactiveMonths
}
if (-not [string]::IsNullOrWhiteSpace($ExportDirectory)) {
    $Arguments.ExportDirectory = $ExportDirectory
}

& $CentralScript @Arguments
