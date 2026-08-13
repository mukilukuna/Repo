<#
.SYNOPSIS
    Inventariseert Active Directory-gebruikers, computers of groepen naar CSV.

.DESCRIPTION
    Dit is de centrale implementatie voor Get-ADUsers.ps1, Get-ADComputers.ps1
    en Get-ADGroups.ps1. Zonder CSVPath wordt de exportlocatie in de terminal gevraagd.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateSet('Users', 'Computers', 'Groups')]
    [string]$ObjectType,

    [string[]]$SearchBase,

    [ValidateSet('true', 'false', 'both')]
    [string]$Enabled = 'true',

    [bool]$GetManager = $true,

    [ValidateSet('include', 'exclude')]
    [string]$Builtin = 'exclude',

    [string]$CSVPath
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\Common\ExportPath.ps1')

if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    throw 'De ActiveDirectory-module is niet gevonden. Installeer de RSAT Active Directory-tools.'
}
Import-Module -Name ActiveDirectory -ErrorAction Stop

$DomainDistinguishedName = (Get-ADDomain -ErrorAction Stop).DistinguishedName
$SearchBases = if ($SearchBase) { @($SearchBase) } else { @($DomainDistinguishedName) }
$DefaultCSVPath = Join-Path 'C:\temp' "AD$($ObjectType)_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$CSVPath = Resolve-ExportFilePath -Path $CSVPath -DefaultPath $DefaultCSVPath -Prompt "CSV-exportbestand voor AD-$ObjectType"

function Get-EnabledFilter {
    param ([Parameter(Mandatory)][string]$Selection)

    switch ($Selection) {
        'true' { return 'Enabled -eq $true' }
        'false' { return 'Enabled -eq $false' }
        default { return '*' }
    }
}

function Get-UserInventory {
    $Properties = @(
        'Name', 'UserPrincipalName', 'Mail', 'Title', 'Enabled', 'Manager',
        'Department', 'TelephoneNumber', 'Office', 'Mobile', 'StreetAddress',
        'City', 'PostalCode', 'State', 'Country', 'Description', 'LastLogonDate',
        'PasswordLastSet'
    )
    $Filter = Get-EnabledFilter -Selection $Enabled

    foreach ($Base in $SearchBases) {
        Write-Host "Gebruikers ophalen uit $Base" -ForegroundColor Cyan
        Get-ADUser -Filter $Filter -SearchBase $Base -Properties $Properties -ErrorAction Stop |
            ForEach-Object {
                $ManagerName = ''
                if ($GetManager -and $_.Manager) {
                    try {
                        $ManagerName = (Get-ADUser -Identity $_.Manager -ErrorAction Stop).Name
                    }
                    catch {
                        Write-Warning "Manager van '$($_.Name)' kon niet worden opgehaald: $($_.Exception.Message)"
                    }
                }

                [PSCustomObject]@{
                    Name                = $_.Name
                    UserPrincipalName   = $_.UserPrincipalName
                    EmailAddress        = $_.Mail
                    'Job title'         = $_.Title
                    Manager             = $ManagerName
                    Department          = $_.Department
                    Office              = $_.Office
                    Phone               = $_.TelephoneNumber
                    Mobile              = $_.Mobile
                    Enabled             = $_.Enabled
                    Street              = $_.StreetAddress
                    City                = $_.City
                    'Postal code'       = $_.PostalCode
                    State               = $_.State
                    Country             = $_.Country
                    Description         = $_.Description
                    'Last login'        = $_.LastLogonDate
                    'Password last set' = $_.PasswordLastSet
                }
            }
    }
}

function Get-ComputerInventory {
    $Properties = @(
        'Name', 'CanonicalName', 'OperatingSystem', 'OperatingSystemVersion',
        'LastLogonDate', 'LogonCount', 'BadLogonCount', 'IPv4Address', 'Enabled',
        'WhenCreated'
    )
    $Filter = Get-EnabledFilter -Selection $Enabled

    foreach ($Base in $SearchBases) {
        Write-Host "Computers ophalen uit $Base" -ForegroundColor Cyan
        Get-ADComputer -Filter $Filter -SearchBase $Base -Properties $Properties -ErrorAction Stop |
            ForEach-Object {
                [PSCustomObject]@{
                    Name              = $_.Name
                    CanonicalName     = $_.CanonicalName
                    OS                = $_.OperatingSystem
                    'OS Version'      = $_.OperatingSystemVersion
                    'Last Logon'      = $_.LastLogonDate
                    'Logon Count'     = $_.LogonCount
                    'Bad Logon Count' = $_.BadLogonCount
                    'IP Address'      = $_.IPv4Address
                    Enabled           = if ($_.Enabled) { 'enabled' } else { 'disabled' }
                    'Date created'    = $_.WhenCreated
                }
            }
    }
}

function Get-GroupInventory {
    $Properties = @(
        'Name', 'CanonicalName', 'DistinguishedName', 'GroupCategory', 'GroupScope',
        'ManagedBy', 'MemberOf', 'Created', 'WhenChanged', 'Mail', 'Info', 'Description'
    )

    foreach ($Base in $SearchBases) {
        Write-Host "Groepen ophalen uit $Base" -ForegroundColor Cyan
        Get-ADGroup -Filter * -SearchBase $Base -Properties $Properties -ErrorAction Stop |
            Where-Object {
                $Builtin -eq 'include' -or (
                    $_.DistinguishedName -notlike "*,CN=Users,$DomainDistinguishedName" -and
                    $_.DistinguishedName -notlike "*,CN=Builtin,$DomainDistinguishedName"
                )
            } |
            ForEach-Object {
                $ManagedByName = ''
                if ($_.ManagedBy) {
                    try {
                        $ManagedByName = (Get-ADObject -Identity $_.ManagedBy -Properties Name -ErrorAction Stop).Name
                    }
                    catch {
                        Write-Warning "Beheerder van groep '$($_.Name)' kon niet worden opgehaald: $($_.Exception.Message)"
                    }
                }

                $MemberOfNames = foreach ($ParentGroupDn in @($_.MemberOf)) {
                    try {
                        (Get-ADGroup -Identity $ParentGroupDn -ErrorAction Stop).Name
                    }
                    catch {
                        Write-Warning "Bovenliggende groep '$ParentGroupDn' kon niet worden opgehaald."
                    }
                }

                [PSCustomObject]@{
                    Name          = $_.Name
                    CanonicalName = $_.CanonicalName
                    GroupCategory = $_.GroupCategory
                    GroupScope    = $_.GroupScope
                    Mail          = $_.Mail
                    Description   = $_.Description
                    Info          = $_.Info
                    ManagedBy     = $ManagedByName
                    MemberOf      = $MemberOfNames -join '; '
                    'Date created' = $_.Created
                    'Date changed' = $_.WhenChanged
                }
            }
    }
}

$Report = @(
    switch ($ObjectType) {
        'Users' { Get-UserInventory }
        'Computers' { Get-ComputerInventory }
        'Groups' { Get-GroupInventory }
    }
)

if ($Report.Count -eq 0) {
    throw "Er zijn geen AD-$ObjectType gevonden; er wordt geen leeg CSV-bestand aangemaakt."
}

$Report | Sort-Object Name | Export-Csv -LiteralPath $CSVPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
Write-Host "AD-$ObjectType geëxporteerd naar: $CSVPath" -ForegroundColor Green
