# Script: Office365_Mailbox_NeverExpire.ps1
# Purpose: Office365 Mailbox NeverExpire
Connect-MsolService
Get-MsolUser –UserPrincipalName user7@example.com| Set-MsolUser –PasswordNeverExpires $True
 get-msoluser –UserPrincipalName user7@example.com | ft displayname, passwordneverexpires