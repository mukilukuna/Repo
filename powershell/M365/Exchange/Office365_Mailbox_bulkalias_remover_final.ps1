# Script: Office365_Mailbox_bulkalias_remover_final.ps1
# Purpose: Office365 Mailbox bulkalias remover final

# Controleer en installeer vereiste modules
foreach ($module in @('ExchangeOnlineManagement')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

$Domain = "example.org"
$RemoveSMTPDomain = "smtp:*@$Domain"
 
 
$AllMailboxes = Get-Mailbox | Where-Object {$_.EmailAddresses -clike $RemoveSMTPDomain}
 
 
ForEach ($Mailbox in $AllMailboxes)
{
 
       
   $AllEmailAddress  = $Mailbox.EmailAddresses -cnotlike $RemoveSMTPDomain
   $RemovedEmailAddress = $Mailbox.EmailAddresses -clike $RemoveDomainsmtp
   $MailboxID = $Mailbox.PrimarySmtpAddress 
   $MailboxID | Set-Mailbox -EmailAddresses $AllEmailAddress #-whatif
 
   Write-Host "The follwoing E-mail address where removed $RemovedEmailAddress from $MailboxID Mailbox "
   
 
} 