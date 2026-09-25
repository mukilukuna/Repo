#Requires -Version 5.1
<#
.SYNOPSIS
Installeert applicaties uit een winget JSON-export.
.DESCRIPTION
Vraagt om het exportbestand en installeert standaard de nieuwste beschikbare
versies. Winget kan daarbij bestaande apps bijwerken en om beheerdersrechten
vragen. Instellingen en appgegevens worden niet hersteld.
.PARAMETER ImportFile
Het JSON-bestand van winget export. Zonder deze parameter wordt erom gevraagd.
.PARAMETER UseExportedVersions
Gebruikt versienummers uit de export. Deze versies moeten nog beschikbaar zijn.
.PARAMETER IgnoreUnavailable
Slaat niet-beschikbare pakketten over zodat de overige apps kunnen installeren.
.PARAMETER AcceptAgreements
Accepteert bron- en pakketovereenkomsten zonder aanvullende vragen.
.EXAMPLE
& 'C:\Repo\powershell\Persoonlijk\Import-WingetApps.ps1'
.EXAMPLE
& 'C:\Repo\powershell\Persoonlijk\Import-WingetApps.ps1' -ImportFile 'C:\temp\WingetApps_20260925_100000_000.json' -IgnoreUnavailable -AcceptAgreements
.EXAMPLE
& 'C:\Repo\powershell\Persoonlijk\Import-WingetApps.ps1' -ImportFile 'C:\temp\apps.json' -UseExportedVersions
.LINK
https://learn.microsoft.com/windows/package-manager/winget/import
#>
[CmdletBinding()]
param (
    [string]$ImportFile,
    [switch]$UseExportedVersions,
    [switch]$IgnoreUnavailable,
    [switch]$AcceptAgreements
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$wingetCommand = Get-Command -Name winget.exe -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $wingetCommand) {
    throw 'Winget is niet gevonden. Installeer of werk App Installer bij via de Microsoft Store en open PowerShell opnieuw.'
}

if ([string]::IsNullOrWhiteSpace($ImportFile)) {
    $ImportFile = Read-Host 'Volledig pad naar het winget JSON-exportbestand'
}
if ([string]::IsNullOrWhiteSpace($ImportFile)) {
    throw 'Er is geen importbestand opgegeven.'
}
$ImportFile = [Environment]::ExpandEnvironmentVariables($ImportFile.Trim().Trim('"').Trim("'"))
if (-not (Test-Path -LiteralPath $ImportFile -PathType Leaf)) {
    throw "Het importbestand is niet gevonden: $ImportFile"
}
$ImportFile = (Resolve-Path -LiteralPath $ImportFile).ProviderPath
try {
    $exportData = Get-Content -LiteralPath $ImportFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw "Het importbestand kan niet als JSON worden gelezen: $($_.Exception.Message)"
}
$packages = @($exportData.Sources | ForEach-Object { $_.Packages } | Where-Object { $_.PackageIdentifier })
if ($packages.Count -eq 0) {
    throw 'Het bestand bevat geen winget-pakketten. Kies een JSON-bestand dat met winget export is aangemaakt.'
}

$wingetArguments = @('import', '--import-file', $ImportFile)
if (-not $UseExportedVersions) {
    $wingetArguments += '--ignore-versions'
}
if ($IgnoreUnavailable) {
    $wingetArguments += '--ignore-unavailable'
    Write-Warning 'Niet-beschikbare pakketten worden overgeslagen; daardoor kunnen apps ontbreken na de import.'
}
if ($AcceptAgreements) {
    $wingetArguments += @('--accept-source-agreements', '--accept-package-agreements')
}

Write-Host "Applicaties importeren via winget ($($packages.Count) pakketten) uit: $ImportFile" -ForegroundColor Cyan
& $wingetCommand.Source @wingetArguments
$wingetExitCode = $LASTEXITCODE
if ($wingetExitCode -ne 0) {
    throw "Winget-import is mislukt met afsluitcode $wingetExitCode. Sommige apps kunnen al zijn geinstalleerd. Zie de winget-melding hierboven."
}

Write-Host 'Winget-import voltooid. Controleer de winget-uitvoer op overgeslagen applicaties.' -ForegroundColor Green
