<#
.SYNOPSIS
    Installeert een of meerdere applicaties stil en schrijft een Intune-logbestand.

.EXAMPLE
    .\SCR_APP_Install.ps1

.EXAMPLE
    .\SCR_APP_Install.ps1 -ApplicationPath '.\app1.exe', '.\app2.exe' -LogFileName 'MultiInstallApps.log'
#>

[CmdletBinding()]
param (
    [string[]]$ApplicationPath,

    [ValidateNotNullOrEmpty()]
    [string]$LogFileName = 'InstallApps.log'
)

$ErrorActionPreference = 'Stop'

if (-not $ApplicationPath) {
    $ApplicationPath = @(Join-Path $PSScriptRoot 'setup.exe')
}

$LogDirectory = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
$LogPath = Join-Path $LogDirectory $LogFileName
if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force -ErrorAction Stop | Out-Null
}

function Write-InstallLog {
    param (
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'ERROR')][string]$Level = 'INFO'
    )

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $Entry = "$Timestamp [$Level] $Message"
    $Entry | Out-File -LiteralPath $LogPath -Append -Encoding utf8
    Write-Output $Entry
}

function Install-Application {
    param ([Parameter(Mandatory)][string]$FilePath)

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Write-InstallLog -Message "Bestand niet gevonden: $FilePath" -Level ERROR
        return $false
    }

    Write-InstallLog -Message "Bezig met installeren: $FilePath"
    try {
        $ArgumentList = @('/s', "/v`"REBOOT=ReallySuppress /qn /l*v `"$LogPath`"`"")
        $Process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -ErrorAction Stop
        if ($Process.ExitCode -ne 0) {
            throw "Installer eindigde met afsluitcode $($Process.ExitCode)."
        }

        Write-InstallLog -Message "Installatie voltooid: $FilePath"
        return $true
    }
    catch {
        Write-InstallLog -Message "Installatie mislukt voor $FilePath - $($_.Exception.Message)" -Level ERROR
        return $false
    }
}

Write-InstallLog -Message "Installatiescript gestart voor $($ApplicationPath.Count) applicatie(s)."
$AnyError = $false

foreach ($Path in $ApplicationPath) {
    $ResolvedPath = if ([System.IO.Path]::IsPathRooted($Path)) {
        $Path
    }
    else {
        Join-Path $PSScriptRoot $Path
    }

    if (-not (Install-Application -FilePath $ResolvedPath)) {
        $AnyError = $true
    }
}

if ($AnyError) {
    Write-InstallLog -Message 'Een of meer installaties zijn mislukt. Script eindigt met afsluitcode 1.' -Level ERROR
    exit 1
}

Write-InstallLog -Message 'Alle installaties zijn succesvol afgerond. Script eindigt met afsluitcode 0.'
exit 0
