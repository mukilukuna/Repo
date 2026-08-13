<#
.SYNOPSIS
    Beheert de OneDrive-snelkoppeling en Sync-knop voor een SharePoint Online-tenant.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory)]
    [ValidatePattern('^https://.+-admin\.sharepoint\.com/?$')]
    [string]$AdminUrl,

    [ValidateSet('OneDriveShortcuts', 'TeamSiteSyncButton', 'Both')]
    [string]$Setting = 'Both',

    [ValidateSet('Disabled', 'Enabled')]
    [string]$State = 'Disabled'
)

$ErrorActionPreference = 'Stop'
$ModuleName = 'Microsoft.Online.SharePoint.PowerShell'

if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
    Write-Host "Module '$ModuleName' wordt geïnstalleerd..." -ForegroundColor Yellow
    Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
}
Import-Module -Name $ModuleName -ErrorAction Stop

Connect-SPOService -Url $AdminUrl -ErrorAction Stop

$Disable = $State -eq 'Disabled'
$TenantSettings = @{}
if ($Setting -in @('OneDriveShortcuts', 'Both')) {
    $TenantSettings.DisableAddShortCutsToOneDrive = $Disable
}
if ($Setting -in @('TeamSiteSyncButton', 'Both')) {
    $TenantSettings.HideSyncButtonOnTeamSite = $Disable
}

$Description = "$Setting instellen op $State"
if ($PSCmdlet.ShouldProcess($AdminUrl, $Description)) {
    Set-SPOTenant @TenantSettings -ErrorAction Stop
    Write-Host "SharePoint-instelling '$Setting' staat nu op '$State'." -ForegroundColor Green
}
