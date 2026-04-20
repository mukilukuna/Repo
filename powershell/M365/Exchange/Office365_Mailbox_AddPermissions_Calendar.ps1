# Script: Office365_Mailbox_AddPermissions_Calendar.ps1
# Purpose: Office365 Mailbox AddPermissions Calendar
$LiveCred = Get-Credential
$Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell/ -Credential $LiveCred -Authentication Basic –AllowRedirection
Import-PSSession $Session
Get-MailboxFolderPermission user9@example.com:\agenda 

#DONE
Add-MailboxFolderPermission -Identity user10@example.com:\agenda -user user11@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user12@example.com:\agenda -user user11@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user13@example.com:\agenda -user user11@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user14@example.com:\agenda -user user11@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user15@example.com:\agenda -user user11@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user16@example.com:\agenda -user user11@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user17@example.com:\agenda -user user11@example.com -AccessRights Editor

#Remove-MailboxFolderPermission -Identity user9@example.com:\agenda -user user18@example.com

Add-MailboxFolderPermission -Identity user9@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user12@example.com:\agenda -user user18@example.com -AccessRights Editor
#Add-MailboxFolderPermission -Identity user19@example.com:\agenda -user user20@example.com -AccessRights Editor
#Add-MailboxFolderPermission -Identity user21@example.com:\agenda -user user18@example.com -AccessRights Editor
#Add-MailboxFolderPermission -Identity user22@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user23@example.com:\agenda -user user18@example.com -AccessRights Editor

Add-MailboxFolderPermission -Identity user24@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user25@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user26@example.com:\agenda -user user18@example.com -AccessRights Editor
#Add-MailboxFolderPermission -Identity user27@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user28@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user29@example.com:\agenda -user user18@example.com -AccessRights Editor

Add-MailboxFolderPermission -Identity user30@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user31@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user32@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user33@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user34@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user35@example.com:\agenda -user user18@example.com -AccessRights Editor

Add-MailboxFolderPermission -Identity user36@example.com:\agenda -user user18@example.com -AccessRights Editor
#Add-MailboxFolderPermission -Identity user37@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user38@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user39@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user40@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user41@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user42@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user43@example.com:\agenda -user user18@example.com -AccessRights Editor

Add-MailboxFolderPermission -Identity user44@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user45@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user46@example.com:\agenda -user user18@example.com -AccessRights Editor
Add-MailboxFolderPermission -Identity user47@example.com:\agenda -user user18@example.com -AccessRights Editor
#Add-MailboxFolderPermission -Identity user48@example.com:\agenda -user user18@example.com -AccessRights Editor
#Add-MailboxFolderPermission -Identity user49@example.com:\agenda -user user18@example.com -AccessRights Editor

Add-MailboxFolderPermission -Identity user21@example.com:\agenda -user user18@example.com -AccessRights Editor

