[CmdletBinding()]
param (
    [string]$ExportDirectory,

    [Parameter(DontShow = $true)]
    [switch]$IsolatedGraphProcess
)

if (-not $IsolatedGraphProcess) {
    $PowerShellExecutable = (Get-Command -Name pwsh -CommandType Application -ErrorAction Stop).Source
    $ChildArguments = @(
        '-NoLogo'
        '-NoProfile'
        '-File'
        $PSCommandPath
        '-IsolatedGraphProcess'
    )

    if (-not [string]::IsNullOrWhiteSpace($ExportDirectory)) {
        $ChildArguments += @('-ExportDirectory', $ExportDirectory)
    }

    Write-Host 'Microsoft Graph-inventarisatie wordt in een schone PowerShell-sessie gestart...' -ForegroundColor Cyan
    & $PowerShellExecutable @ChildArguments
    $ChildExitCode = $LASTEXITCODE

    if ($ChildExitCode -ne 0) {
        throw "De geïsoleerde Microsoft Graph-inventarisatie is mislukt met afsluitcode $ChildExitCode."
    }

    return
}

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\..\Common\ExportPath.ps1')
$ExportDirectory = Resolve-ExportDirectory -Path $ExportDirectory

# Controleer en installeer vereiste modules
$requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Users')
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
}

$loadedGraphCore = [AppDomain]::CurrentDomain.GetAssemblies() |
    Where-Object { $_.GetName().Name -eq 'Microsoft.Graph.Core' } |
    Select-Object -First 1
if ($loadedGraphCore -and $loadedGraphCore.GetName().Version.Major -lt 3) {
    throw "Er is al een verouderde Microsoft.Graph.Core-assembly geladen, meestal via PnP.PowerShell. Sluit deze PowerShell-sessie en voer dit script uit in een schone sessie met: pwsh -NoProfile -File `"$PSCommandPath`""
}

$authenticationVersions = Get-Module -ListAvailable -Name Microsoft.Graph.Authentication |
    Select-Object -ExpandProperty Version
$graphModuleVersion = Get-Module -ListAvailable -Name Microsoft.Graph.Users |
    Select-Object -ExpandProperty Version |
    Where-Object { $authenticationVersions -contains $_ } |
    Sort-Object -Descending |
    Select-Object -First 1
if (-not $graphModuleVersion) {
    throw 'Microsoft.Graph.Authentication en Microsoft.Graph.Users hebben geen gelijke geïnstalleerde versie. Werk beide modules bij en start PowerShell opnieuw.'
}

Import-Module -Name Microsoft.Graph.Authentication -RequiredVersion $graphModuleVersion -ErrorAction Stop
Import-Module -Name Microsoft.Graph.Users -RequiredVersion $graphModuleVersion -ErrorAction Stop

Connect-MgGraph -Scopes "User.Read.All", "AuditLog.Read.All", "Directory.Read.All" -ErrorAction Stop
# Datum voor de bestandsnaam
$datum = Get-Date -Format "yyyyMMdd"

# Haal alle gebruikers op met de benodigde eigenschappen
$users = @(
    Get-MgUser -All -Property DisplayName, UserPrincipalName, MailNickname, JobTitle, AssignedLicenses, OnPremisesSyncEnabled, UserType, SignInActivity -ErrorAction Stop
)
if ($users.Count -eq 0) {
    throw 'Er zijn geen gebruikers gevonden. Er wordt geen CSV-bestand aangemaakt.'
}

# Maak een array om de resultaten op te slaan
$result = @()

foreach ($user in $users) {
    # Bepaal het type gebruiker
    switch ($user.UserType) {
        "Member" {
            if ($user.MailNickname -like "*shared*") {
                $userType = "Shared"
            }
            else {
                $userType = "User"
            }
        }
        "Guest" { $userType = "Guest" }
        default { $userType = "External" }
    }

    # Controleer of de gebruiker een licentie heeft
    $hasLicense = if ($user.AssignedLicenses.Count -gt 0) { "Ja" } else { "Nee" }

    # Controleer of de gebruiker gesynchroniseerd is met Active Directory
    $adSynced = if ($user.OnPremisesSyncEnabled -eq $true) { "Ja" } else { "Nee" }

    # Haal de laatste aanmeldingsdatum op
    $lastSignIn = if ($user.SignInActivity.LastSignInDateTime) { $user.SignInActivity.LastSignInDateTime } else { "Nooit aangemeld" }

    # Voeg de gegevens toe aan de resultaten
    $result += [PSCustomObject]@{
        Naam                  = $user.DisplayName
        Email                 = $user.UserPrincipalName
        Type                  = $userType
        Functie               = $user.JobTitle
        Licentie              = $hasLicense
        ActiveDirectorySynced = $adSynced
        LaatsteAanmelding     = $lastSignIn
        GastExternGebruiker   = $user.UserType
    }
}

# Exporteer de resultaten naar een CSV-bestand
$OutputPath = Join-Path -Path $ExportDirectory -ChildPath "AzureAD_Gebruikers_$datum.csv"
$result | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
Write-Host "Resultaten geëxporteerd naar: $OutputPath" -ForegroundColor Green
