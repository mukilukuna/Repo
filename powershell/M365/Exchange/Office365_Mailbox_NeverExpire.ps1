# Script: Office365_Mailbox_NeverExpire.ps1
# Purpose: Office365 Mailbox NeverExpire

# Controleer en installeer vereiste modules
foreach ($module in @('MSOnline')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

Connect-MsolService
Get-MsolUser –UserPrincipalName user7@example.com| Set-MsolUser –PasswordNeverExpires $True
 get-msoluser –UserPrincipalName user7@example.com | ft displayname, passwordneverexpires