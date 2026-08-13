<#
.SYNOPSIS
    Voegt gebruikers uit CSV toe aan één of meerdere Active Directory-groepen.

.DESCRIPTION
    Met Mode SingleGroup bevat het CSV-bestand één gebruikerswaarde per regel en
    wordt iedere gebruiker aan GroupName toegevoegd. Met Mode PerRow bevat het
    CSV-bestand kolommen voor de gebruiker en de bijbehorende groep.

.EXAMPLE
    .\Add-UsersToGroup.ps1 -Mode SingleGroup -GroupName 'SG_PowerBi' -Path C:\temp\users.csv -Filter DisplayName -WhatIf

.EXAMPLE
    .\Add-UsersToGroup.ps1 -Mode PerRow -Path C:\temp\users-groups.csv -UserColumn User -GroupColumn Group -WhatIf
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [ValidateSet('SingleGroup', 'PerRow')]
    [string]$Mode = 'SingleGroup',

    [string]$GroupName,

    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$Path,

    [char]$Delimiter = ',',

    [ValidateSet('DisplayName', 'Email', 'UserPrincipalName')]
    [string]$Filter = 'DisplayName',

    [string]$UserColumn = 'User',

    [string]$GroupColumn = 'Group'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw 'De ActiveDirectory-module is niet gevonden. Installeer de RSAT Active Directory-tools.'
}
Import-Module -Name ActiveDirectory -ErrorAction Stop

if ($Mode -eq 'SingleGroup' -and [string]::IsNullOrWhiteSpace($GroupName)) {
    throw 'GroupName is verplicht bij Mode SingleGroup.'
}

$Rows = if ($Mode -eq 'SingleGroup') {
    Import-Csv -LiteralPath $Path -Delimiter $Delimiter -Header $UserColumn
}
else {
    Import-Csv -LiteralPath $Path -Delimiter $Delimiter
}

foreach ($Row in $Rows) {
    $UserValue = [string]$Row.$UserColumn
    $TargetGroup = if ($Mode -eq 'SingleGroup') { $GroupName } else { [string]$Row.$GroupColumn }

    if ([string]::IsNullOrWhiteSpace($UserValue) -or [string]::IsNullOrWhiteSpace($TargetGroup)) {
        Write-Warning 'CSV-regel overgeslagen: gebruiker of groep ontbreekt.'
        continue
    }

    $EscapedUserValue = $UserValue.Replace("'", "''")
    $User = Get-ADUser -Filter "$Filter -eq '$EscapedUserValue'" -ErrorAction Stop |
        Select-Object -First 1

    if (-not $User) {
        Write-Warning "Gebruiker '$UserValue' is niet gevonden in Active Directory."
        continue
    }

    if ($PSCmdlet.ShouldProcess("$UserValue -> $TargetGroup", 'Toevoegen aan AD-groep')) {
        Add-ADGroupMember -Identity $TargetGroup -Members $User -ErrorAction Stop
        Write-Host "Gebruiker '$UserValue' toegevoegd aan '$TargetGroup'." -ForegroundColor Green
    }
}
