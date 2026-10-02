#Requires -Version 5.1
<#
.SYNOPSIS
Exporteert de door winget herkende applicaties naar een JSON-bestand.
.DESCRIPTION
Vraagt om een exportmap (standaard C:\temp) en maakt een bestand met datum
en tijd. Bewaart ook versienummers. Dit is een applicatielijst, geen back-up
van instellingen, licenties of appgegevens. Niet-herkende apps worden door
winget gemeld en ontbreken in de export.
.PARAMETER ExportDirectory
De map voor de export. Zonder deze parameter wordt om de map gevraagd.
.PARAMETER AcceptAgreements
Accepteert de bronovereenkomsten van winget zonder aanvullende vragen.
.EXAMPLE
& 'C:\Repo\powershell\Persoonlijk\Export-WingetApps.ps1'
.EXAMPLE
& 'C:\Repo\powershell\Persoonlijk\Export-WingetApps.ps1' -ExportDirectory 'C:\temp' -AcceptAgreements
.LINK
https://learn.microsoft.com/windows/package-manager/winget/export
#>
[CmdletBinding()]
param (
    [string]$ExportDirectory,
    [switch]$AcceptAgreements
)

$ErrorActionPreference = 'Stop'
# Behandel de afsluitcode zelf, ook als de aanroepende sessie dit heeft aangezet.
$PSNativeCommandUseErrorActionPreference = $false

$wingetCommand = Get-Command -Name winget.exe -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $wingetCommand) {
    throw 'Winget is niet gevonden. Installeer of werk App Installer bij via de Microsoft Store en open PowerShell opnieuw.'
}

. (Join-Path $PSScriptRoot '..\Common\ExportPath.ps1')
$ExportDirectory = Resolve-ExportDirectory -Path $ExportDirectory
$fileName = 'WingetApps_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff')
$outputPath = Join-Path -Path $ExportDirectory -ChildPath $fileName
if (Test-Path -LiteralPath $outputPath) {
    throw "Het exportbestand bestaat al: $outputPath. Start de export opnieuw."
}

$wingetArguments = @('export', '--output', $outputPath, '--include-versions')
if ($AcceptAgreements) {
    $wingetArguments += '--accept-source-agreements'
}

Write-Host 'Applicatielijst exporteren via winget...' -ForegroundColor Cyan
& $wingetCommand.Source @wingetArguments
$wingetExitCode = $LASTEXITCODE
if ($wingetExitCode -ne 0) {
    throw "Winget-export is mislukt met afsluitcode $wingetExitCode. Zie de winget-melding hierboven. Een eventueel aangemaakt bestand kan onvolledig zijn: $outputPath"
}
if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
    throw "Winget heeft geen exportbestand aangemaakt: $outputPath"
}

Write-Host "Applicatielijst opgeslagen in: $outputPath" -ForegroundColor Green
