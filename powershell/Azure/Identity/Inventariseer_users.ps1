[CmdletBinding()]
param (
    [string]$ExportDirectory,

    [ValidateSet('AllUsers', 'InactiveGuests', 'Both')]
    [string]$ReportType = 'Both',

    [ValidateRange(1, 120)]
    [int]$InactiveMonths = 3,

    [Parameter(DontShow = $true)]
    [switch]$IsolatedGraphProcess
)

if (-not $IsolatedGraphProcess) {
    $PowerShellExecutable = Join-Path -Path $PSHOME -ChildPath 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $PowerShellExecutable -PathType Leaf)) {
        $PowerShellExecutable = Get-Command -Name pwsh -All -CommandType Application -ErrorAction Stop |
            Select-Object -ExpandProperty Source -Unique |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
    }
    if ([string]::IsNullOrWhiteSpace($PowerShellExecutable)) {
        throw 'PowerShell 7 (pwsh.exe) is niet gevonden. Installeer PowerShell 7 of voeg pwsh.exe toe aan PATH.'
    }

    $ChildArguments = @(
        '-NoLogo'
        '-NoProfile'
        '-File'
        $PSCommandPath
        '-IsolatedGraphProcess'
        '-ReportType'
        $ReportType
        '-InactiveMonths'
        $InactiveMonths.ToString()
    )

    if (-not [string]::IsNullOrWhiteSpace($ExportDirectory)) {
        $ChildArguments += @('-ExportDirectory', $ExportDirectory)
    }

    Write-Host 'Microsoft Graph-inventarisatie wordt in een schone PowerShell-sessie gestart...' -ForegroundColor Cyan
    try {
        & $PowerShellExecutable @ChildArguments
        $ChildExitCode = $LASTEXITCODE
    }
    catch {
        throw "De schone PowerShell-sessie kon niet worden gestart via '$PowerShellExecutable': $($_.Exception.Message)"
    }

    if ($null -eq $ChildExitCode -or $ChildExitCode -ne 0) {
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

if ($ReportType -in @('AllUsers', 'Both')) {
    $result = foreach ($user in $users) {
        # Graph bevat geen betrouwbaar mailboxtype. Deze classificatie beschrijft het accounttype.
        $userType = switch ($user.UserType) {
            'Member' { 'User' }
            'Guest' { 'Guest' }
            default { 'External' }
        }

        $hasLicense = if ($user.AssignedLicenses.Count -gt 0) { 'Ja' } else { 'Nee' }
        $adSynced = if ($user.OnPremisesSyncEnabled -eq $true) { 'Ja' } else { 'Nee' }
        $lastSignIn = if ($user.SignInActivity.LastSignInDateTime) {
            $user.SignInActivity.LastSignInDateTime
        }
        else {
            'Nooit aangemeld'
        }

        [PSCustomObject]@{
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

    $OutputPath = Join-Path -Path $ExportDirectory -ChildPath "AzureAD_Gebruikers_$datum.csv"
    $result | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    Write-Host "Alle gebruikers geëxporteerd naar: $OutputPath" -ForegroundColor Green
}

if ($ReportType -in @('InactiveGuests', 'Both')) {
    $DateThreshold = (Get-Date).AddMonths(-$InactiveMonths)
    $inactiveGuestUsers = @(
        $users | Where-Object {
            $_.UserType -eq 'Guest' -and (
                -not $_.SignInActivity.LastSignInDateTime -or
                [DateTime]$_.SignInActivity.LastSignInDateTime -lt $DateThreshold
            )
        }
    )

    $InactiveGuestReport = $inactiveGuestUsers |
        Select-Object DisplayName, UserPrincipalName, UserType,
            @{Name = 'LastSignInDateTime'; Expression = { $_.SignInActivity.LastSignInDateTime } },
            @{Name = 'InactiveMonthsThreshold'; Expression = { $InactiveMonths } }

    $InactiveGuestOutputPath = Join-Path -Path $ExportDirectory -ChildPath "InactieveGastGebruikers_$datum.csv"
    $InactiveGuestReport | Export-Csv -LiteralPath $InactiveGuestOutputPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
    Write-Host "Inactieve gasten geëxporteerd naar: $InactiveGuestOutputPath" -ForegroundColor Green
}
