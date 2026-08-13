[CmdletBinding()]
param (
    [string]$ExportDirectory
)

function Resolve-ExportDirectory {
    param (
        [string]$Path,
        [string]$DefaultPath = 'C:\temp'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Read-Host "Exportmap (druk op Enter voor '$DefaultPath')"
    }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $DefaultPath
    }

    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path -Path (Get-Location).ProviderPath -ChildPath $Path
    }

    $Path = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    elseif (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Het exportpad is geen map: $Path"
    }

    return $Path
}

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

Connect-MgGraph -Scopes "User.Read.All", "AuditLog.Read.All", "Directory.Read.All"
# Datum voor de bestandsnaam
$datum = Get-Date -Format "yyyyMMdd"

# Haal alle gebruikers op met de benodigde eigenschappen
$users = Get-MgUser -All -Property DisplayName, UserPrincipalName, JobTitle, AssignedLicenses, OnPremisesSyncEnabled, UserType, SignInActivity

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
$result | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "Resultaten geëxporteerd naar: $OutputPath" -ForegroundColor Green
