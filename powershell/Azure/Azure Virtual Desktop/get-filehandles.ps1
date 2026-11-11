$ErrorActionPreference = 'Stop'

# Benodigde modules - installatie voor alle gebruikers
foreach ($Module in @('Az.Accounts', 'Az.Storage')) {
    if (-not (Get-Module -ListAvailable -Name $Module)) {
        Install-Module -Name $Module -Scope AllUsers -Force
    }
}

Import-Module Az.Accounts
Import-Module Az.Storage

# Aanmelden bij Azure
if (-not (Get-AzContext)) {
    Connect-AzAccount -UseDeviceAuthentication
}

# Subscription selecteren
$Subscription = Get-AzSubscription |
    Out-GridView -Title 'Selecteer Storax subscription' -PassThru

if (-not $Subscription) {
    throw 'Geen subscription geselecteerd.'
}

Set-AzContext -SubscriptionId $Subscription.Id | Out-Null

# Storageaccount
$StorageAccount = Get-AzStorageAccount `
    -ResourceGroupName 'STX-EUAZU-RSG-STOR' `
    -Name 'stxeuazusto'

$Ctx = $StorageAccount.Context

# File share
$ShareName = 'fslogix'

Write-Host "`nOpen SMB-handles ophalen..." -ForegroundColor Cyan

# Alle handles inclusief submappen
$Handles = @(
    Get-AzStorageFileHandle `
        -Context $Ctx `
        -ShareName $ShareName `
        -Recursive
)

Write-Host "`nAantal gevonden handles: $($Handles.Count)" -ForegroundColor Green

# Overzicht
$Handles |
    Select-Object Path, HandleId, ClientIp, ClientName,
                  OpenTime, LastReconnectTime, SessionId |
    Sort-Object Path, OpenTime |
    Format-Table -AutoSize