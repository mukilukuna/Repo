# Script: Office365_Mailbox_SentitemsShared.ps1
# Purpose: Office365 Mailbox SentitemsShared

# Controleer en installeer vereiste modules
foreach ($module in @('ExchangeOnlineManagement')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

set-mailbox <mailbox name> -MessageCopyForSentAsEnabled $True