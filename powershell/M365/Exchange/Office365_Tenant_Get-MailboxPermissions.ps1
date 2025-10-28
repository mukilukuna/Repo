# Script: Office365_Tenant_Get-MailboxPermissions.ps1
# Purpose: Office365 Tenant Get MailboxPermissions
Write-Host "Fetching mailboxes"
$Mbx = Get-ExoMailbox -RecipientTypeDetails UserMailbox, SharedMailbox -ResultSize Unlimited -PropertySet Delivery -Properties RecipientTypeDetails, DisplayName | Select DisplayName, UserPrincipalName, RecipientTypeDetails, GrantSendOnBehalfTo
If ($Mbx.Count -eq 0) { 
    Write-Error "No mailboxes found. Script exiting..." -ErrorAction Stop 
} 
$Report = [System.Collections.Generic.List[Object]]::new() # Create output file 
$ProgressDelta = 100 / ($Mbx.count); $PercentComplete = 0; $MbxNumber = 0
ForEach ($M in $Mbx) {
    $MbxNumber++
    $MbxStatus = $M.DisplayName + " [" + $MbxNumber + "/" + $Mbx.Count + "]"
    Write-Progress -Activity "Checking permissions for mailbox" -Status $MbxStatus -PercentComplete $PercentComplete
    $PercentComplete += $ProgressDelta
    $Permissions = Get-ExoRecipientPermission -Identity $M.UserPrincipalName | ? { $_.Trustee -ne "NT AUTHORITY\SELF" }
    If ($Null -ne $Permissions) {
        # Grab information about SendAs permission and output it into the report
        ForEach ($Permission in $Permissions) {
            $ReportLine = [PSCustomObject] @{
                Mailbox     = $M.DisplayName
                UPN         = $M.UserPrincipalName
                Permission  = $Permission | Select -ExpandProperty AccessRights
                AssignedTo  = $Permission.Trustee
                MailboxType = $M.RecipientTypeDetails 
            } 
            $Report.Add($ReportLine) 
        }
    }

    # Grab information about FullAccess permissions
    $Permissions = Get-ExoMailboxPermission -Identity $M.UserPrincipalName | ? { $_.User -Like "*@*" }    
    If ($Null -ne $Permissions) {
        # Grab each permission and output it into the report
        ForEach ($Permission in $Permissions) {
            $ReportLine = [PSCustomObject] @{
                Mailbox     = $M.DisplayName
                UPN         = $M.UserPrincipalName
                Permission  = $Permission | Select -ExpandProperty AccessRights
                AssignedTo  = $Permission.User
                MailboxType = $M.RecipientTypeDetails 
            } 
            $Report.Add($ReportLine) 
        }
    } 

    # Check if this mailbox has granted Send on Behalf of permission to anyone
    If (![string]::IsNullOrEmpty($M.GrantSendOnBehalfTo)) {
        ForEach ($Permission in $M.GrantSendOnBehalfTo) {
            $ReportLine = [PSCustomObject] @{
                Mailbox     = $M.DisplayName
                UPN         = $M.UserPrincipalName
                Permission  = "Send on Behalf Of"
                AssignedTo  = (Get-ExoRecipient -Identity $Permission).PrimarySmtpAddress
                MailboxType = $M.RecipientTypeDetails 
            } 
            $Report.Add($ReportLine) 
        }
    }
}

$Report | Sort -Property @{Expression = { $_.MailboxType }; Ascending = $False }, Mailbox | Export-CSV c:\temp\MailboxPermissions.csv -NoTypeInformation -Encoding UTF8
Write-Host "All done." $Mbx.Count "mailboxes scanned."