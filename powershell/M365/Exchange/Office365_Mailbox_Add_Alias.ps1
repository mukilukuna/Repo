# Script: Office365_Mailbox_Add_Alias.ps1
# Purpose: Office365 Mailbox Add Alias

# Controleer en installeer vereiste modules
foreach ($module in @('ExchangeOnlineManagement')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

Connect-ExchangeOnline
Set-Mailbox "iTunes en Playstore Accounts" -EmailAddresses @{add="user8@example.com"}