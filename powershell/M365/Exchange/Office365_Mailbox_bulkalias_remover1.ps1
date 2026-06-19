
# Controleer en installeer vereiste modules
foreach ($module in @('ExchangeOnlineManagement')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

# Get all mailboxes
$Mailboxes = Get-Mailbox -ResultSize Unlimited

# Loop through each mailbox
foreach ($Mailbox in $Mailboxes) {

    # Change @contoso.com to the domain that you want to remove
    $Mailbox.EmailAddresses | Where-Object { ($_ -clike "smtp*") -and ($_ -like "*@example.org") } | 

    # Perform operation on each item
    ForEach-Object {

        # Remove the -WhatIf parameter after you tested and are sure to remove the secondary email addresses
        Set-Mailbox $Mailbox.Name -EmailAddresses @{remove = $_ } -WhatIf

        # Write output
        Write-Host "Removing $_ from $Mailbox Mailbox" -ForegroundColor Green
    }
}

Stop-Transcript