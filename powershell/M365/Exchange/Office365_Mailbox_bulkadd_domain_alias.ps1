# Script: Office365_Mailbox_bulkadd_domain_alias.ps1
# Purpose: Office365 Mailbox bulkadd domain alias
Connect-ExchangeOnline

$users = Get-Mailbox -ResultSize Unlimited | Where-Object{$_.PrimarySMTPAddress -match "org3.nl"}#
 
foreach($user in $users){
    $newUpn = $user.UserPrincipalName.Replace(‘org3.nl’,’example.org’)
    Write-Host "Adding Alias" $newUpn
    Set-Mailbox $user.PrimarySmtpAddress -EmailAddresses @{add="$newUpn"}
}

$users = Get-Mailbox -ResultSize Unlimited | Where-Object{$_.PrimarySMTPAddress -match "org5.nl"}
 
foreach($user in $users){
    $newUpn = $user.UserPrincipalName.Replace(‘org5.nl’,’example.org’)
    Write-Host "Adding Alias" $newUpn
    Set-Mailbox $user.PrimarySmtpAddress -EmailAddresses @{add="$newUpn"}
}

$users = Get-Mailbox -ResultSize Unlimited | Where-Object{$_.PrimarySMTPAddress -match "org4.nl"}
 
foreach($user in $users){
    $newUpn = $user.UserPrincipalName.Replace(‘org4.nl’,’example.org’)
    Write-Host "Adding Alias" $newUpn
    Set-Mailbox $user.PrimarySmtpAddress -EmailAddresses @{add="$newUpn"}
}

$users = Get-Mailbox -ResultSize Unlimited | Where-Object{$_.PrimarySMTPAddress -match "org2.nl"}
 
foreach($user in $users){
    $newUpn = $user.UserPrincipalName.Replace(‘org2.nl’,’example.org’)
    Write-Host "Adding Alias" $newUpn
    Set-Mailbox $user.PrimarySmtpAddress -EmailAddresses @{add="$newUpn"}
}