<#
.SYNOPSIS
    Compatibiliteitswrapper voor SCR_APP_Install.ps1 met de bestaande drie installers.
#>

[CmdletBinding()]
param ()

$CentralScript = Join-Path $PSScriptRoot 'SCR_APP_Install.ps1'
$ApplicationPaths = @(
    'CR Integration\SAP Business One Crystal Report Integration Package.exe'
    'Crystal Server Integration\BOERuntime_x64.exe'
    'Client.x64\setup.exe'
)

& $CentralScript -ApplicationPath $ApplicationPaths -LogFileName 'MultiInstallApps.log'
