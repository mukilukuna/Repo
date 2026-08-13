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
foreach ($module in @('Microsoft.Graph')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

# Stap 2: Maak verbinding met Microsoft Graph met de benodigde machtigingen
Connect-MgGraph -Scopes "User.Read.All", "AuditLog.Read.All", "Directory.Read.All"

# Stap 3: Definieer de periode (3 maanden geleden)
$DateThreshold = (Get-Date).AddMonths(-3)

# Stap 4: Haal alle gastgebruikers op
$guestUsers = Get-MgUser -All -Filter "userType eq 'Guest'" -Property "DisplayName", "UserPrincipalName", "UserType", "SignInActivity"

# Stap 5: Filter gebruikers die langer dan 3 maanden niet hebben ingelogd
$inactiveGuestUsers = $guestUsers | Where-Object {
    if ($_.SignInActivity.LastSignInDateTime) {
        [DateTime]$_.SignInActivity.LastSignInDateTime -lt $DateThreshold
    }
    else {
        # Als er geen aanmeldingsgegevens zijn, beschouw de gebruiker als nooit aangemeld
        $true
    }
}

# Stap 6: Selecteer de gewenste eigenschappen
$inactiveGuestUsers | Select-Object DisplayName, UserPrincipalName, @{Name = "LastSignInDateTime"; Expression = { $_.SignInActivity.LastSignInDateTime } }

# Stap 7: Exporteer de lijst naar een CSV-bestand
$OutputPath = Join-Path -Path $ExportDirectory -ChildPath 'InactieveGastGebruikers.csv'
$inactiveGuestUsers |
    Select-Object DisplayName, UserPrincipalName, @{Name = "LastSignInDateTime"; Expression = { $_.SignInActivity.LastSignInDateTime } } |
    Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "Resultaten geëxporteerd naar: $OutputPath" -ForegroundColor Green
