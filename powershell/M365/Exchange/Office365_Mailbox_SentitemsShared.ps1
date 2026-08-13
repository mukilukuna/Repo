<#
.SYNOPSIS
    Schakelt het opslaan van via Send As verzonden berichten in de gedeelde mailbox in of uit.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [Parameter(Mandatory)]
    [string]$Mailbox,

    [bool]$Enabled = $true
)

$ErrorActionPreference = 'Stop'
$ModuleName = 'ExchangeOnlineManagement'

if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
    Write-Host "Module '$ModuleName' wordt geïnstalleerd..." -ForegroundColor Yellow
    Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
}
Import-Module -Name $ModuleName -ErrorAction Stop

Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop

$Description = "MessageCopyForSentAsEnabled instellen op $Enabled"
if ($PSCmdlet.ShouldProcess($Mailbox, $Description)) {
    Set-Mailbox -Identity $Mailbox -MessageCopyForSentAsEnabled $Enabled -ErrorAction Stop
    Write-Host "De instelling voor '$Mailbox' staat nu op '$Enabled'." -ForegroundColor Green
}
