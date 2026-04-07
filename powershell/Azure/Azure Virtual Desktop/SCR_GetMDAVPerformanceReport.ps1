# Script: Get-MDAVPerformanceReport-Full.ps1
# Purpose: Maak een Microsoft Defender Performance Analyzer scan en exporteer de resultaten naar TXT
<#
Zorg ervoor dat het volgende is ingesteld:
1. Start PowerShell of PowerShell ISE als administrator.
2. Microsoft Defender cmdlets New-MpPerformanceRecording en Get-MpPerformanceReport moeten beschikbaar zijn.
3. De map C:\temp moet schrijfbaar zijn.
4. Tijdens de recording moet je het performanceprobleem reproduceren.

Gemaakt door: Muki Lukuna samen met ChatGPT
#>

# Variabelen
$WorkingFolder = 'C:\temp'
$RecordingPath = Join-Path -Path $WorkingFolder -ChildPath 'MDAV_Recording.etl'
$ReportPath = Join-Path -Path $WorkingFolder -ChildPath 'MDAV_Performance_Report.txt'
$TopCount = 100
$TopPathsDepth = 20
$StartTime = Get-Date

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ReportSectionData {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ReportObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    if ($null -eq $ReportObject) {
        return $null
    }

    if ($ReportObject.PSObject.Properties.Name -contains $PropertyName) {
        return $ReportObject.$PropertyName
    }

    return $ReportObject
}

function Add-ReportSection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $false)]
        [object]$Data,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Add-Content -Path $Path -Value ('=' * 100) -Encoding UTF8
    Add-Content -Path $Path -Value $Title -Encoding UTF8
    Add-Content -Path $Path -Value ('=' * 100) -Encoding UTF8

    if ($null -eq $Data -or @($Data).Count -eq 0) {
        Add-Content -Path $Path -Value 'Geen resultaten gevonden.' -Encoding UTF8
        Add-Content -Path $Path -Value '' -Encoding UTF8
        return
    }

    $FormattedData = $Data | Select-Object * | Format-Table -AutoSize | Out-String -Width 4096
    Add-Content -Path $Path -Value $FormattedData.TrimEnd() -Encoding UTF8
    Add-Content -Path $Path -Value '' -Encoding UTF8
}

# Controleer administratorrechten
if (-not (Test-IsAdministrator)) {
    throw 'Fout: start PowerShell of PowerShell ISE als administrator en voer het script opnieuw uit.'
}

# Controleer of de Defender Performance cmdlets beschikbaar zijn
if (-not (Get-Command -Name 'New-MpPerformanceRecording' -ErrorAction SilentlyContinue)) {
    throw 'Fout: de cmdlet New-MpPerformanceRecording is niet beschikbaar op dit systeem.'
}

if (-not (Get-Command -Name 'Get-MpPerformanceReport' -ErrorAction SilentlyContinue)) {
    throw 'Fout: de cmdlet Get-MpPerformanceReport is niet beschikbaar op dit systeem.'
}

# Maak de werkmap aan als deze nog niet bestaat
if (-not (Test-Path -Path $WorkingFolder)) {
    New-Item -Path $WorkingFolder -ItemType Directory -Force | Out-Null
}

# Verwijder oude bestanden zodat je zeker weet dat je met een nieuwe scan werkt
if (Test-Path -Path $RecordingPath) {
    Remove-Item -Path $RecordingPath -Force
}

if (Test-Path -Path $ReportPath) {
    Remove-Item -Path $ReportPath -Force
}

Write-Host ''
Write-Host 'Microsoft Defender Performance Analyzer script wordt gestart...' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Voor het maken van de scan wordt het volgende commando gebruikt:' -ForegroundColor Yellow
Write-Host 'New-MpPerformanceRecording -RecordTo C:\temp\MDAV_Recording.etl' -ForegroundColor Green
Write-Host ''
Write-Host 'De recording wordt nu gestart.' -ForegroundColor Yellow
Write-Host 'Reproduceer nu het Defender performanceprobleem.' -ForegroundColor Yellow
Write-Host 'Druk daarna op Enter om de recording op te slaan.' -ForegroundColor Yellow
Write-Host ''

# Start de recording
try {
    New-MpPerformanceRecording -RecordTo $RecordingPath
}
catch {
    if ($_.Exception.Message -match 'already recording') {
        throw "Fout: er draait al een Windows Performance Recorder trace. Voer eerst dit uit en probeer daarna opnieuw:`n`n    wpr -cancel -instancename MSFT_MpPerformanceRecording"
    }

    throw $_
}

# Controleer of het ETL-bestand bestaat en geldig is
if (-not (Test-Path -Path $RecordingPath)) {
    throw "Fout: het ETL-bestand is niet gevonden op $RecordingPath . Controleer of de recording correct is aangemaakt voordat je de analyse uitvoert."
}

$RecordingFile = Get-Item -Path $RecordingPath -ErrorAction Stop

if ($RecordingFile.Extension -ne '.etl') {
    throw "Fout: het gevonden bestand is geen .etl-bestand: $($RecordingFile.FullName)"
}

if ($RecordingFile.Length -eq 0) {
    throw "Fout: het ETL-bestand is leeg: $($RecordingFile.FullName)"
}

Write-Host ''
Write-Host 'ETL-bestand gevonden. De analyse wordt nu uitgevoerd...' -ForegroundColor Cyan
Write-Host ''

# Haal de verschillende rapporten op
$TopPathsReportObject = Get-MpPerformanceReport -Path $RecordingPath -TopPaths $TopCount -TopPathsDepth $TopPathsDepth -Raw
$TopExtensionsReportObject = Get-MpPerformanceReport -Path $RecordingPath -TopExtensions $TopCount -Raw
$TopFilesReportObject = Get-MpPerformanceReport -Path $RecordingPath -TopFiles $TopCount -Raw
$TopProcessesReportObject = Get-MpPerformanceReport -Path $RecordingPath -TopProcesses $TopCount -Raw

$TopPathsData = Get-ReportSectionData -ReportObject $TopPathsReportObject -PropertyName 'TopPaths'
$TopExtensionsData = Get-ReportSectionData -ReportObject $TopExtensionsReportObject -PropertyName 'TopExtensions'
$TopFilesData = Get-ReportSectionData -ReportObject $TopFilesReportObject -PropertyName 'TopFiles'
$TopProcessesData = Get-ReportSectionData -ReportObject $TopProcessesReportObject -PropertyName 'TopProcesses'

# Header voor het TXT-rapport
$Header = @(
    'Microsoft Defender Antivirus Performance Analyzer Report',
    '',
    "Aangemaakt op : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "Start opname : $($StartTime.ToString('yyyy-MM-dd HH:mm:ss'))",
    "ETL bestand  : $RecordingPath",
    "TXT rapport  : $ReportPath",
    '',
    'De scan is eerst gemaakt met het volgende commando:',
    'New-MpPerformanceRecording -RecordTo C:\temp\MDAV_Recording.etl',
    '',
    'Pas nadat deze recording is opgeslagen, wordt de analyse uitgevoerd.',
    ''
)

Set-Content -Path $ReportPath -Value $Header -Encoding UTF8

# Voeg de rapportonderdelen toe aan het TXT-bestand
Add-ReportSection -Title "Top $TopCount paden"      -Data $TopPathsData      -Path $ReportPath
Add-ReportSection -Title "Top $TopCount extensies"  -Data $TopExtensionsData -Path $ReportPath
Add-ReportSection -Title "Top $TopCount bestanden"  -Data $TopFilesData      -Path $ReportPath
Add-ReportSection -Title "Top $TopCount processen"  -Data $TopProcessesData  -Path $ReportPath

Write-Host 'Klaar.' -ForegroundColor Green
Write-Host "ETL-bestand: $RecordingPath" -ForegroundColor Green
Write-Host "TXT-rapport: $ReportPath" -ForegroundColor Green