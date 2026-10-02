# ============================================================
# BitTitan Tenant-to-Tenant Migration - Inventarisatie
# Doel:
# - Users / Microsoft 365 licenties
# - Exchange mailboxen + grootte + archives
# - Shared / Room / Equipment mailboxes
# - Public Folders
# - OneDrive
# - SharePoint sites
# - SharePoint document libraries + grootte (optioneel via PnP)
# - Teams
# - Devices
# - Samenvatting voor BitTitan licensing
#
# Vereisten:
# - PowerShell 7 op Windows
# - PowerShell als Administrator starten
# - Global Reader / passende adminrollen
# - Exchange Administrator voor Exchange inventarisatie
# - SharePoint Administrator voor SharePoint inventarisatie
#
# Ontbrekende PowerShell 7-modules worden met -Scope AllUsers geïnstalleerd.
# De klassieke SharePoint Online-module wordt afzonderlijk in de
# Windows PowerShell 5.1-modulemap gecontroleerd en zo nodig geïnstalleerd.
# ============================================================

[CmdletBinding()]
param (
    [string]$ExportDirectory,

    [Parameter(DontShow = $true)]
    [switch]$RunInCurrentProcess
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Start altijd in een schoon PowerShell 7-proces
# ------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
    throw "Sla dit script eerst op als .ps1-bestand en voer daarna het bestand uit. Uitvoering als geplakte selectie wordt niet ondersteund."
}

if ($PSVersionTable.PSEdition -ne "Core" -or
    $PSVersionTable.PSVersion.Major -lt 7) {

    $PowerShell7 = Get-Command pwsh.exe -ErrorAction SilentlyContinue

    if ($null -eq $PowerShell7) {
        throw "PowerShell 7 is vereist, maar pwsh.exe is niet gevonden."
    }

    $ChildArguments = @(
        '-NoLogo'
        '-NoProfile'
        '-File'
        $PSCommandPath
        '-RunInCurrentProcess'
    )
    if (-not [string]::IsNullOrWhiteSpace($ExportDirectory)) {
        $ChildArguments += @('-ExportDirectory', $ExportDirectory)
    }

    & $PowerShell7.Source @ChildArguments
    $ChildExitCode = $LASTEXITCODE

    if ($ChildExitCode -ne 0) {
        throw "Het geïsoleerde PowerShell 7-proces is gestopt met exitcode $ChildExitCode."
    }

    return
}

if (-not $RunInCurrentProcess) {

    $CurrentPowerShell = (Get-Process -Id $PID).Path

    Write-Host "Script wordt opnieuw gestart in een schoon PowerShell 7-proces..." -ForegroundColor DarkGray

    $ChildArguments = @(
        '-NoLogo'
        '-NoProfile'
        '-File'
        $PSCommandPath
        '-RunInCurrentProcess'
    )
    if (-not [string]::IsNullOrWhiteSpace($ExportDirectory)) {
        $ChildArguments += @('-ExportDirectory', $ExportDirectory)
    }

    & $CurrentPowerShell @ChildArguments
    $ChildExitCode = $LASTEXITCODE

    if ($ChildExitCode -ne 0) {
        throw "Het geïsoleerde PowerShell 7-proces is gestopt met exitcode $ChildExitCode."
    }

    return
}
# ------------------------------------------------------------
# Controle: Administrator
# ------------------------------------------------------------

$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)
$IsAdmin = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdmin) {
    Write-Host ""
    Write-Host "PowerShell is niet als Administrator gestart." -ForegroundColor Red
    Write-Host "Start PowerShell 7 als Administrator en voer het script opnieuw uit." -ForegroundColor Yellow
    return
}

# ------------------------------------------------------------
# Instellingen
# ------------------------------------------------------------

. (Join-Path $PSScriptRoot '..\..\Common\ExportPath.ps1')

$ExportDirectory = Resolve-ExportDirectory `
    -Path $ExportDirectory `
    -DefaultPath 'C:\Temp' `
    -Prompt 'Exportmap voor de BitTitan-inventarisatie'

$TimeStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$OutputFolder = Join-Path -Path $ExportDirectory -ChildPath "BitTitan_Inventory_$TimeStamp"

New-Item -ItemType Directory -Path $OutputFolder -Force -ErrorAction Stop | Out-Null

Write-Host "Uitvoermap: $OutputFolder" -ForegroundColor Green

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " BitTitan Tenant Migration - Inventarisatie" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$TenantId = Read-Host "Voer Tenant ID of klanttenant.onmicrosoft.com in"

$DelegatedOrganization = Read-Host @"
Gebruik je GDAP voor Exchange?
Voer dan klanttenant.onmicrosoft.com in.
Gebruik je rechtstreeks een klant-adminaccount? Laat dit dan leeg
"@

$SPOAdminUrl = Read-Host @"
Voer de SharePoint Admin URL in.
Voorbeeld: https://contoso-admin.sharepoint.com
"@

$PnPClientId = Read-Host @"
Optioneel: voer PnP Entra App Client ID in voor EXACTE document-library groottes.
Laat leeg als je deze nog niet hebt
"@

# ------------------------------------------------------------
# Modules controleren en zo nodig herstellen
# ------------------------------------------------------------

function Ensure-PowerShellModule {
    param (
        [Parameter(Mandatory)]
        [string]$Name
    )

    $Module = Get-Module -ListAvailable -Name $Name |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($null -eq $Module) {
        Write-Host "Module ontbreekt: $Name" -ForegroundColor Yellow
        Write-Host "Installeren voor alle gebruikers..." -ForegroundColor Yellow

        Install-Module -Name $Name -Scope AllUsers -Repository PSGallery -Force -AllowClobber -ErrorAction Stop

        $Module = Get-Module -ListAvailable -Name $Name |
            Sort-Object Version -Descending |
            Select-Object -First 1
    }

    if ($null -eq $Module) {
        throw "Module $Name is na de installatie niet vindbaar in PSModulePath."
    }

    Write-Host "Module gereed: $Name $($Module.Version)" -ForegroundColor Green
}

function Initialize-SharePointOnlineModule {

    $WindowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

    if (-not (Test-Path -LiteralPath $WindowsPowerShell)) {
        throw "Windows PowerShell 5.1 is niet gevonden op $WindowsPowerShell."
    }

    # PowerShell 7 en Windows PowerShell 5.1 gebruiken verschillende
    # CurrentUser- en AllUsers-modulemappen. Controleer en installeer de
    # SPO-module daarom binnen het Windows PowerShell-proces zelf.
    $BootstrapScript = @'
$ErrorActionPreference = "Stop"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $ModuleName = "Microsoft.Online.SharePoint.PowerShell"
    $Module = Get-Module -ListAvailable -Name $ModuleName |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($null -eq $Module) {
        if (-not (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
            throw "Install-Module is niet beschikbaar in Windows PowerShell 5.1."
        }

        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        }

        Install-Module -Name $ModuleName -Scope AllUsers -Repository PSGallery -Force -AllowClobber -ErrorAction Stop

        $Module = Get-Module -ListAvailable -Name $ModuleName |
            Sort-Object Version -Descending |
            Select-Object -First 1
    }

    if ($null -eq $Module) {
        throw "$ModuleName is na de installatie niet vindbaar in Windows PowerShell 5.1."
    }

    Import-Module -Name $Module.Path -DisableNameChecking -Force -ErrorAction Stop

    Write-Output (
        "SPO_MODULE_READY|{0}|{1}" -f $Module.Version, $Module.ModuleBase
    )

    exit 0
}
catch {
    [Console]::Error.WriteLine($_.Exception.ToString())
    exit 1
}
'@

    $EncodedBootstrap = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($BootstrapScript)
    )

    $BootstrapOutput = @(
        & $WindowsPowerShell -NoLogo -NoProfile -NonInteractive -EncodedCommand $EncodedBootstrap 2>&1
    )

    $BootstrapExitCode = $LASTEXITCODE
    $ReadyLine = $BootstrapOutput |
        Where-Object { [string]$_ -like "SPO_MODULE_READY|*" } |
        Select-Object -Last 1

    if ($BootstrapExitCode -ne 0 -or $null -eq $ReadyLine) {
        $Details = ($BootstrapOutput | Out-String).Trim()

        throw "De SharePoint Online-module kon niet in Windows PowerShell 5.1 worden voorbereid. $Details"
    }

    $ReadyParts = ([string]$ReadyLine) -split '\|', 3
    Write-Host "Module gereed: Microsoft.Online.SharePoint.PowerShell $($ReadyParts[1])" -ForegroundColor Green
    Write-Host "Windows PowerShell-modulepad: $($ReadyParts[2])" -ForegroundColor DarkGray

    # Een bestaande compatibiliteitssessie behoudt de oude modulezoekroute.
    # Verwijder die sessie zodat de zojuist geïnstalleerde module zichtbaar is.
    Get-Module -Name Microsoft.Online.SharePoint.PowerShell |
        Remove-Module -Force -ErrorAction SilentlyContinue

    Get-PSSession -Name WinPSCompatSession -ErrorAction SilentlyContinue |
        Remove-PSSession -ErrorAction SilentlyContinue

    Import-Module Microsoft.Online.SharePoint.PowerShell `
        -UseWindowsPowerShell `
        -DisableNameChecking `
        -Force `
        -ErrorAction Stop

    $MissingCommands = @(
        "Connect-SPOService",
        "Get-SPOSite"
    ) | Where-Object {
        -not (Get-Command -Name $_ -ErrorAction SilentlyContinue)
    }

    if ($MissingCommands.Count -gt 0) {
        throw "De SharePoint-module is geïmporteerd, maar cmdlets ontbreken: $($MissingCommands -join ', ')."
    }
}

Ensure-PowerShellModule "Microsoft.Graph.Authentication"
Ensure-PowerShellModule "ExchangeOnlineManagement"

if (-not [string]::IsNullOrWhiteSpace($PnPClientId)) {
    Ensure-PowerShellModule "PnP.PowerShell"
}

# ------------------------------------------------------------
# Modules importeren
# ------------------------------------------------------------

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Get-MgContext | Out-Null

Import-Module ExchangeOnlineManagement -ErrorAction Stop

Initialize-SharePointOnlineModule

if (-not [string]::IsNullOrWhiteSpace($PnPClientId)) {
    Import-Module PnP.PowerShell -ErrorAction Stop
}

# ------------------------------------------------------------
# Hulpfuncties
# ------------------------------------------------------------

function Export-InventoryCsv {
    param (
        [Parameter(Mandatory)]
        $Data,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    $Path = Join-Path $OutputFolder $FileName

    $Data |
        Export-Csv `
            -Path $Path `
            -Delimiter ";" `
            -NoTypeInformation `
            -Encoding utf8BOM

    Write-Host "Aangemaakt: $Path" -ForegroundColor DarkGreen
}

function Invoke-GraphPagedRequest {
    param (
        [Parameter(Mandatory)]
        [string]$Uri
    )

    $Results = @()

    do {
        $Response = Invoke-MgGraphRequest `
            -Method GET `
            -Uri $Uri `
            -OutputType PSObject

        if ($null -ne $Response.value) {
            $Results += $Response.value
            $Uri = $Response.'@odata.nextLink'
        }
        else {
            $Results += $Response
            $Uri = $null
        }

    } while ($Uri)

    return $Results
}

function Convert-ExchangeSizeToGB {
    param (
        $Size
    )

    if ($null -eq $Size) {
        return 0
    }

    # Probeer eerst ByteQuantifiedSize
    try {
        if ($Size.Value -and
            $Size.Value.PSObject.Methods.Name -contains "ToBytes") {

            return [Math]::Round(
                ($Size.Value.ToBytes() / 1GB),
                3
            )
        }
    }
    catch {}

    # Fallback voor geremote/deserialized Exchange objecten
    $StringValue = [string]$Size

    if ($StringValue -match '\(([0-9\.,\s]+)\sbytes\)') {

        $BytesString = $Matches[1] -replace '[^0-9]', ''

        if ($BytesString) {
            return [Math]::Round(
                ([double]$BytesString / 1GB),
                3
            )
        }
    }

    return 0
}

function Get-ObjectPropertyValue {
    param (
        $Object,
        [string]$Property
    )

    if ($Object.PSObject.Properties.Name -contains $Property) {
        return $Object.$Property
    }

    return $null
}

# ------------------------------------------------------------
# Verbinden met Microsoft Graph
# ------------------------------------------------------------

Write-Host ""
Write-Host "Verbinden met Microsoft Graph..." -ForegroundColor Cyan

$GraphScopes = @(
    "User.Read.All",
    "Group.Read.All",
    "Directory.Read.All",
    "Device.Read.All",
    "Sites.Read.All"
)

Connect-MgGraph `
    -TenantId $TenantId `
    -Scopes $GraphScopes `
    -NoWelcome

$GraphContext = Get-MgContext

Write-Host "Graph tenant: $($GraphContext.TenantId)" -ForegroundColor Green
Write-Host "Graph account: $($GraphContext.Account)" -ForegroundColor Green

# ------------------------------------------------------------
# Verbinden met Exchange Online
# ------------------------------------------------------------

Write-Host ""
Write-Host "Verbinden met Exchange Online..." -ForegroundColor Cyan

if ([string]::IsNullOrWhiteSpace($DelegatedOrganization)) {

    Connect-ExchangeOnline `
        -ShowBanner:$false
}
else {

    Connect-ExchangeOnline `
        -DelegatedOrganization $DelegatedOrganization `
        -ShowBanner:$false
}

# ------------------------------------------------------------
# Verbinden met SharePoint Online
# ------------------------------------------------------------

Write-Host ""
Write-Host "Verbinden met SharePoint Online..." -ForegroundColor Cyan

Connect-SPOService `
    -Url $SPOAdminUrl `
    -ModernAuth $true `
    -AuthenticationUrl "https://login.microsoftonline.com/organizations" `
    -UseSystemBrowser $true

# ============================================================
# 1. Microsoft 365 SKU's
# ============================================================

Write-Host ""
Write-Host "[1] Microsoft 365 productlicenties ophalen..." -ForegroundColor Cyan

$SubscribedSkus = Invoke-GraphPagedRequest `
    -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus?$select=skuId,skuPartNumber,consumedUnits,prepaidUnits'

$SkuMap = @{}

$SkuOutput = foreach ($Sku in $SubscribedSkus) {

    $SkuMap[[string]$Sku.skuId] = $Sku.skuPartNumber

    [PSCustomObject]@{
        Product             = $Sku.skuPartNumber
        SkuId               = $Sku.skuId
        ConsumedUnits       = $Sku.consumedUnits
        EnabledUnits        = $Sku.prepaidUnits.enabled
        SuspendedUnits      = $Sku.prepaidUnits.suspended
        WarningUnits        = $Sku.prepaidUnits.warning
    }
}

Export-InventoryCsv $SkuOutput "01_M365_ProductLicenses.csv"

# ============================================================
# 2. Users
# ============================================================

Write-Host ""
Write-Host "[2] Entra gebruikers ophalen..." -ForegroundColor Cyan

$UsersRaw = Invoke-GraphPagedRequest `
    -Uri 'https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,mail,userType,accountEnabled,assignedLicenses,onPremisesSyncEnabled'

$Users = foreach ($User in $UsersRaw) {

    $AssignedSkuNames = @()

    foreach ($AssignedLicense in @($User.assignedLicenses)) {

        $SkuId = [string]$AssignedLicense.skuId

        if ($SkuMap.ContainsKey($SkuId)) {
            $AssignedSkuNames += $SkuMap[$SkuId]
        }
        else {
            $AssignedSkuNames += $SkuId
        }
    }

    [PSCustomObject]@{
        DisplayName            = $User.displayName
        UserPrincipalName      = $User.userPrincipalName
        Mail                   = $User.mail
        UserType               = $User.userType
        AccountEnabled         = $User.accountEnabled
        OnPremisesSyncEnabled  = $User.onPremisesSyncEnabled
        HasM365License         = (@($User.assignedLicenses).Count -gt 0)
        Licenses               = ($AssignedSkuNames -join ", ")
        ObjectId               = $User.id
    }
}

Export-InventoryCsv $Users "02_Users.csv"

# ============================================================
# 3. Groups + Teams
# ============================================================

Write-Host ""
Write-Host "[3] Groups en Teams ophalen..." -ForegroundColor Cyan

$GroupsRaw = Invoke-GraphPagedRequest `
    -Uri 'https://graph.microsoft.com/v1.0/groups?$select=id,displayName,mail,mailEnabled,securityEnabled,groupTypes,resourceProvisioningOptions,visibility'

$Groups = foreach ($Group in $GroupsRaw) {

    $IsTeam = @($Group.resourceProvisioningOptions) -contains "Team"
    $IsM365Group = @($Group.groupTypes) -contains "Unified"

    $GroupType = if ($IsTeam) {
        "Microsoft Team"
    }
    elseif ($IsM365Group) {
        "Microsoft 365 Group"
    }
    elseif ($Group.mailEnabled -and $Group.securityEnabled) {
        "Mail-enabled security group"
    }
    elseif ($Group.mailEnabled) {
        "Distribution group"
    }
    else {
        "Security group"
    }

    [PSCustomObject]@{
        DisplayName       = $Group.displayName
        Mail              = $Group.mail
        GroupType         = $GroupType
        IsTeam            = $IsTeam
        Visibility        = $Group.visibility
        MailEnabled       = $Group.mailEnabled
        SecurityEnabled   = $Group.securityEnabled
        GroupId           = $Group.id
    }
}

Export-InventoryCsv $Groups "03_Groups.csv"

$TeamGroups = @(
    $Groups |
        Where-Object IsTeam -eq $true
)

# ============================================================
# 4. Exchange mailboxen
# ============================================================

Write-Host ""
Write-Host "[4] Exchange mailboxen en groottes ophalen..." -ForegroundColor Cyan
Write-Host "Dit kan een aantal minuten duren..." -ForegroundColor DarkGray

$MailboxesRaw = Get-EXOMailbox `
    -ResultSize Unlimited `
    -RecipientTypeDetails UserMailbox,SharedMailbox,RoomMailbox,EquipmentMailbox `
    -Properties ArchiveStatus,ArchiveGuid

$MailboxResults = @()

$Counter = 0

foreach ($Mailbox in $MailboxesRaw) {

    $Counter++

    Write-Progress `
        -Activity "Mailbox inventarisatie" `
        -Status "$Counter / $($MailboxesRaw.Count) - $($Mailbox.PrimarySmtpAddress)" `
        -PercentComplete (($Counter / $MailboxesRaw.Count) * 100)

    $PrimaryStats = $null
    $ArchiveStats = $null

    try {
        $PrimaryStats = Get-EXOMailboxStatistics `
            -Identity $Mailbox.PrimarySmtpAddress
    }
    catch {
        Write-Warning "Mailboxstatistieken niet opgehaald voor $($Mailbox.PrimarySmtpAddress)"
    }

    if ($Mailbox.ArchiveStatus -eq "Active") {

        try {
            $ArchiveStats = Get-EXOMailboxStatistics `
                -Identity $Mailbox.PrimarySmtpAddress `
                -Archive
        }
        catch {
            Write-Warning "Archive-statistieken niet opgehaald voor $($Mailbox.PrimarySmtpAddress)"
        }
    }

    $PrimaryGB = Convert-ExchangeSizeToGB $PrimaryStats.TotalItemSize
    $ArchiveGB = Convert-ExchangeSizeToGB $ArchiveStats.TotalItemSize

    $MailboxResults += [PSCustomObject]@{
        DisplayName          = $Mailbox.DisplayName
        UserPrincipalName    = $Mailbox.UserPrincipalName
        PrimarySmtpAddress   = $Mailbox.PrimarySmtpAddress
        RecipientType        = $Mailbox.RecipientTypeDetails

        MailboxSizeGB        = $PrimaryGB
        MailboxItemCount     = $PrimaryStats.ItemCount

        ArchiveEnabled       = ($Mailbox.ArchiveStatus -eq "Active")
        ArchiveSizeGB        = $ArchiveGB
        ArchiveItemCount     = $ArchiveStats.ItemCount

        TotalExchangeGB      = [Math]::Round(
            ($PrimaryGB + $ArchiveGB),
            3
        )

        ExternalDirectoryId  = $Mailbox.ExternalDirectoryObjectId
    }
}

Write-Progress -Activity "Mailbox inventarisatie" -Completed

Export-InventoryCsv $MailboxResults "04_Exchange_Mailboxes.csv"

# ============================================================
# 5. Public Folders
# ============================================================

Write-Host ""
Write-Host "[5] Public Folders controleren..." -ForegroundColor Cyan

$PublicFolderResults = @()

try {

    $PublicFolderStats = Get-PublicFolderStatistics `
        -ResultSize Unlimited `
        -ErrorAction Stop

    foreach ($Folder in $PublicFolderStats) {

        $PublicFolderResults += [PSCustomObject]@{
            Name                 = $Folder.Name
            FolderPath           = $Folder.FolderPath
            ItemCount            = $Folder.ItemCount
            SizeGB               = Convert-ExchangeSizeToGB $Folder.TotalItemSize
            LastModificationTime = $Folder.LastModificationTime
        }
    }
}
catch {
    Write-Host "Geen Public Folders gevonden of niet toegankelijk." -ForegroundColor DarkGray
}

if ($PublicFolderResults.Count -gt 0) {
    Export-InventoryCsv $PublicFolderResults "05_PublicFolders.csv"
}

# ============================================================
# 6. SharePoint + OneDrive sites
# ============================================================

Write-Host ""
Write-Host "[6] SharePoint en OneDrive sites ophalen..." -ForegroundColor Cyan

$SPOSitesRaw = Get-SPOSite `
    -IncludePersonalSite $true `
    -Limit ALL

$SPOSiteResults = @()
$OneDriveResults = @()

foreach ($Site in $SPOSitesRaw) {

    $IsOneDrive = (
        $Site.Url -like "*-my.sharepoint.com/personal/*" -or
        $Site.Template -like "SPSPERS*"
    )

    $StorageGB = [Math]::Round(
        ([double]$Site.StorageUsageCurrent / 1024),
        3
    )

    if ($IsOneDrive) {

        $OneDriveResults += [PSCustomObject]@{
            Owner           = $Site.Owner
            Url             = $Site.Url
            StorageGB       = $StorageGB
            StorageMB       = $Site.StorageUsageCurrent
            Status          = $Site.Status
            LastContentModifiedDate = $Site.LastContentModifiedDate
        }
    }
    else {

        $GroupId = Get-ObjectPropertyValue $Site "GroupId"
        $RelatedGroupId = Get-ObjectPropertyValue $Site "RelatedGroupId"
        $IsTeamsConnected = Get-ObjectPropertyValue $Site "IsTeamsConnected"
        $IsTeamsChannelConnected = Get-ObjectPropertyValue $Site "IsTeamsChannelConnected"

        $SPOSiteResults += [PSCustomObject]@{
            Title                    = $Site.Title
            Url                      = $Site.Url
            Template                 = $Site.Template
            Owner                    = $Site.Owner
            StorageGB                = $StorageGB
            StorageMB                = $Site.StorageUsageCurrent
            GroupId                  = $GroupId
            RelatedGroupId           = $RelatedGroupId
            IsTeamsConnected         = $IsTeamsConnected
            IsTeamsChannelConnected  = $IsTeamsChannelConnected
            Status                   = $Site.Status
            LastContentModifiedDate  = $Site.LastContentModifiedDate
        }
    }
}

Export-InventoryCsv $SPOSiteResults "06_SharePoint_Sites.csv"
Export-InventoryCsv $OneDriveResults "07_OneDrive.csv"

# ============================================================
# 7. Document Libraries
# ============================================================

Write-Host ""
Write-Host "[7] SharePoint document libraries inventariseren..." -ForegroundColor Cyan

$DocumentLibraryResults = @()

if (-not [string]::IsNullOrWhiteSpace($PnPClientId)) {

    Write-Host ""
    Write-Host "PnP Client ID opgegeven." -ForegroundColor Green
    Write-Host "Document-library groottes worden exact via SharePoint Storage Metrics bepaald." -ForegroundColor Green

    $SiteCounter = 0

    foreach ($Site in $SPOSiteResults) {

        $SiteCounter++

        # Redirect sites overslaan
        if ($Site.Template -like "REDIRECTSITE*") {
            continue
        }

        Write-Progress `
            -Activity "SharePoint document libraries" `
            -Status "$SiteCounter / $($SPOSiteResults.Count) - $($Site.Url)" `
            -PercentComplete (($SiteCounter / $SPOSiteResults.Count) * 100)

        try {

            $PnPConnection = Connect-PnPOnline `
                -Url $Site.Url `
                -Interactive `
                -ClientId $PnPClientId `
                -ReturnConnection

            $Libraries = Get-PnPList `
                -Connection $PnPConnection `
                -Includes RootFolder |
                Where-Object {
                    $_.BaseTemplate -eq 101 -and
                    $_.Hidden -eq $false
                }

            foreach ($Library in $Libraries) {

                try {

                    $StorageMetric = Get-PnPFolderStorageMetric `
                        -List $Library.Id `
                        -Connection $PnPConnection

                    $LibraryGB = [Math]::Round(
                        ([double]$StorageMetric.TotalSize / 1GB),
                        3
                    )

                    $Required100GBUnits = [Math]::Max(
                        1,
                        [Math]::Ceiling($LibraryGB / 100)
                    )

                    $DocumentLibraryResults += [PSCustomObject]@{
                        SiteTitle                = $Site.Title
                        SiteUrl                  = $Site.Url
                        LibraryName              = $Library.Title
                        LibraryId                = $Library.Id
                        LibraryUrl               = $Library.RootFolder.ServerRelativeUrl
                        SizeGB                   = $LibraryGB
                        FileCount                = $StorageMetric.TotalFileCount
                        IsTeamsConnected         = $Site.IsTeamsConnected
                        IsTeamsChannelConnected  = $Site.IsTeamsChannelConnected
                        GroupId                  = $Site.GroupId
                        RelatedGroupId           = $Site.RelatedGroupId
                        Min100GBUnitsIfMigrated  = $Required100GBUnits
                    }
                }
                catch {

                    Write-Warning "Storage Metrics mislukt: $($Site.Url) / $($Library.Title)"

                    $DocumentLibraryResults += [PSCustomObject]@{
                        SiteTitle                = $Site.Title
                        SiteUrl                  = $Site.Url
                        LibraryName              = $Library.Title
                        LibraryId                = $Library.Id
                        LibraryUrl               = $Library.RootFolder.ServerRelativeUrl
                        SizeGB                   = $null
                        FileCount                = $null
                        IsTeamsConnected         = $Site.IsTeamsConnected
                        IsTeamsChannelConnected  = $Site.IsTeamsChannelConnected
                        GroupId                  = $Site.GroupId
                        RelatedGroupId           = $Site.RelatedGroupId
                        Min100GBUnitsIfMigrated  = 1
                    }
                }
            }

            Disconnect-PnPOnline -Connection $PnPConnection
        }
        catch {
            Write-Warning "PnP toegang mislukt voor $($Site.Url): $($_.Exception.Message)"
        }
    }

    Write-Progress -Activity "SharePoint document libraries" -Completed
}
else {

    Write-Host ""
    Write-Host "Geen PnP Client ID opgegeven." -ForegroundColor Yellow
    Write-Host "Librarynamen worden via Graph opgehaald, maar exacte library-groottes ontbreken." -ForegroundColor Yellow
    Write-Host "Voor definitieve BitTitan Shared Document aantallen raad ik PnP Storage Metrics aan." -ForegroundColor Yellow

    foreach ($Site in $SPOSiteResults) {

        if ($Site.Template -like "REDIRECTSITE*") {
            continue
        }

        try {

            $UriObject = [Uri]$Site.Url
            $HostName = $UriObject.Host
            $RelativePath = $UriObject.AbsolutePath

            if ([string]::IsNullOrWhiteSpace($RelativePath)) {
                $RelativePath = "/"
            }

            $GraphSiteUri =
                "https://graph.microsoft.com/v1.0/sites/${HostName}:$RelativePath"

            $GraphSite = Invoke-MgGraphRequest `
                -Method GET `
                -Uri $GraphSiteUri `
                -OutputType PSObject

            $DriveUri =
                "https://graph.microsoft.com/v1.0/sites/$($GraphSite.id)/drives"

            $Drives = Invoke-GraphPagedRequest -Uri $DriveUri

            foreach ($Drive in $Drives) {

                if ($Drive.driveType -ne "documentLibrary") {
                    continue
                }

                $DocumentLibraryResults += [PSCustomObject]@{
                    SiteTitle                = $Site.Title
                    SiteUrl                  = $Site.Url
                    LibraryName              = $Drive.name
                    LibraryId                = $Drive.id
                    LibraryUrl               = $Drive.webUrl
                    SizeGB                   = $null
                    FileCount                = $null
                    IsTeamsConnected         = $Site.IsTeamsConnected
                    IsTeamsChannelConnected  = $Site.IsTeamsChannelConnected
                    GroupId                  = $Site.GroupId
                    RelatedGroupId           = $Site.RelatedGroupId
                    Min100GBUnitsIfMigrated  = 1
                }
            }
        }
        catch {
            Write-Warning "Libraries niet opgehaald voor $($Site.Url)"
        }
    }
}

Export-InventoryCsv $DocumentLibraryResults "08_SharePoint_DocumentLibraries.csv"

# ============================================================
# 8. Teams + geschatte dataomvang
# ============================================================

Write-Host ""
Write-Host "[8] Teams licensing-overzicht maken..." -ForegroundColor Cyan

$TeamsResults = foreach ($Team in $TeamGroups) {

    $TeamId = [string]$Team.GroupId

    $RelatedSites = @(
        $SPOSiteResults |
            Where-Object {
                ([string]$_.GroupId -eq $TeamId) -or
                ([string]$_.RelatedGroupId -eq $TeamId)
            }
    )

    $EstimatedTeamGB = 0

    if ($RelatedSites.Count -gt 0) {

        $EstimatedTeamGB = (
            $RelatedSites |
                Measure-Object `
                    -Property StorageGB `
                    -Sum
        ).Sum
    }

    if ($null -eq $EstimatedTeamGB) {
        $EstimatedTeamGB = 0
    }

    $EstimatedFCL = [Math]::Max(
        1,
        [Math]::Ceiling($EstimatedTeamGB / 100)
    )

    [PSCustomObject]@{
        TeamName                       = $Team.DisplayName
        TeamId                         = $TeamId
        Mail                           = $Team.Mail
        Visibility                     = $Team.Visibility
        ConnectedSharePointSites       = $RelatedSites.Count
        EstimatedStorageGB             = [Math]::Round($EstimatedTeamGB, 3)
        Estimated100GBLicenseUnits     = $EstimatedFCL
    }
}

Export-InventoryCsv $TeamsResults "09_Teams.csv"

# ============================================================
# 9. Devices
# ============================================================

Write-Host ""
Write-Host "[9] Entra devices ophalen..." -ForegroundColor Cyan

$DevicesRaw = Invoke-GraphPagedRequest `
    -Uri 'https://graph.microsoft.com/v1.0/devices?$select=id,deviceId,displayName,operatingSystem,operatingSystemVersion,trustType,isManaged,isCompliant,accountEnabled,approximateLastSignInDateTime'

$Devices = foreach ($Device in $DevicesRaw) {

    [PSCustomObject]@{
        DisplayName               = $Device.displayName
        OperatingSystem           = $Device.operatingSystem
        OperatingSystemVersion    = $Device.operatingSystemVersion
        JoinType                  = $Device.trustType
        Managed                   = $Device.isManaged
        Compliant                 = $Device.isCompliant
        AccountEnabled            = $Device.accountEnabled
        LastSignIn                = $Device.approximateLastSignInDateTime
        DeviceId                  = $Device.deviceId
        ObjectId                  = $Device.id
    }
}

Export-InventoryCsv $Devices "10_Devices.csv"

# ============================================================
# 10. BitTitan licensing samenvatting
# ============================================================

Write-Host ""
Write-Host "[10] BitTitan licentie-input berekenen..." -ForegroundColor Cyan

$UserMailboxes = @(
    $MailboxResults |
        Where-Object RecipientType -eq "UserMailbox"
)

$SharedMailboxes = @(
    $MailboxResults |
        Where-Object RecipientType -eq "SharedMailbox"
)

$RoomMailboxes = @(
    $MailboxResults |
        Where-Object RecipientType -eq "RoomMailbox"
)

$EquipmentMailboxes = @(
    $MailboxResults |
        Where-Object RecipientType -eq "EquipmentMailbox"
)

$ArchiveMailboxes = @(
    $MailboxResults |
        Where-Object ArchiveEnabled -eq $true
)

$OneDrivesWithData = @(
    $OneDriveResults |
        Where-Object StorageGB -gt 0
)

$WindowsDevices = @(
    $Devices |
        Where-Object OperatingSystem -like "Windows*"
)

$PublicFolderGB = 0

if ($PublicFolderResults.Count -gt 0) {
    $PublicFolderGB = (
        $PublicFolderResults |
            Measure-Object `
                -Property SizeGB `
                -Sum
    ).Sum
}

if ($null -eq $PublicFolderGB) {
    $PublicFolderGB = 0
}

$PublicFolderLicenses = 0

if ($PublicFolderGB -gt 0) {
    $PublicFolderLicenses = [Math]::Ceiling(
        $PublicFolderGB / 10
    )
}

# Alleen libraries die NIET aan Teams zijn gekoppeld
$StandaloneSharePointLibraries = @(
    $DocumentLibraryResults |
        Where-Object {
            $_.IsTeamsConnected -ne $true -and
            $_.IsTeamsChannelConnected -ne $true
        }
)

$SharePoint100GBUnits = 0

if ($StandaloneSharePointLibraries.Count -gt 0) {

    $SharePoint100GBUnits = (
        $StandaloneSharePointLibraries |
            Measure-Object `
                -Property Min100GBUnitsIfMigrated `
                -Sum
    ).Sum
}

if ($null -eq $SharePoint100GBUnits) {
    $SharePoint100GBUnits = 0
}

$Team100GBUnits = 0

if ($TeamsResults.Count -gt 0) {

    $Team100GBUnits = (
        $TeamsResults |
            Measure-Object `
                -Property Estimated100GBLicenseUnits `
                -Sum
    ).Sum
}

if ($null -eq $Team100GBUnits) {
    $Team100GBUnits = 0
}

$Summary = @(
    [PSCustomObject]@{
        Category = "Entra Member Users"
        Count = @($Users | Where-Object UserType -eq "Member").Count
        BitTitanRelevance = "Identity / user scope"
    }

    [PSCustomObject]@{
        Category = "Licensed M365 Users"
        Count = @($Users | Where-Object HasM365License -eq $true).Count
        BitTitanRelevance = "Controle brongebruikers"
    }

    [PSCustomObject]@{
        Category = "User Mailboxes"
        Count = $UserMailboxes.Count
        BitTitanRelevance = "UMB / Tenant Migration Bundle kandidaten"
    }

    [PSCustomObject]@{
        Category = "Shared Mailboxes"
        Count = $SharedMailboxes.Count
        BitTitanRelevance = "Apart beoordelen voor mailboxmigratie"
    }

    [PSCustomObject]@{
        Category = "Room Mailboxes"
        Count = $RoomMailboxes.Count
        BitTitanRelevance = "Apart beoordelen"
    }

    [PSCustomObject]@{
        Category = "Equipment Mailboxes"
        Count = $EquipmentMailboxes.Count
        BitTitanRelevance = "Apart beoordelen"
    }

    [PSCustomObject]@{
        Category = "Archive Enabled Mailboxes"
        Count = $ArchiveMailboxes.Count
        BitTitanRelevance = "Archive inbegrepen bij UMB/TMB"
    }

    [PSCustomObject]@{
        Category = "Provisioned OneDrives"
        Count = $OneDriveResults.Count
        BitTitanRelevance = "UMB/TMB"
    }

    [PSCustomObject]@{
        Category = "OneDrives with Data"
        Count = $OneDrivesWithData.Count
        BitTitanRelevance = "UMB/TMB"
    }

    [PSCustomObject]@{
        Category = "Microsoft Teams"
        Count = $TeamsResults.Count
        BitTitanRelevance = "Minimaal 1 FCL/Collaboration unit per Team"
    }

    [PSCustomObject]@{
        Category = "Estimated Team 100GB Units"
        Count = $Team100GBUnits
        BitTitanRelevance = "FCL / Collaboration licenses"
    }

    [PSCustomObject]@{
        Category = "Standalone SharePoint Document Libraries"
        Count = $StandaloneSharePointLibraries.Count
        BitTitanRelevance = "Per document library licenseren"
    }

    [PSCustomObject]@{
        Category = "Estimated SharePoint 100GB Units"
        Count = $SharePoint100GBUnits
        BitTitanRelevance = "FCL / Shared Document licenses"
    }

    [PSCustomObject]@{
        Category = "Public Folder Data GB"
        Count = [Math]::Round($PublicFolderGB, 3)
        BitTitanRelevance = "10 GB per Public Folder license"
    }

    [PSCustomObject]@{
        Category = "Estimated Public Folder Licenses"
        Count = $PublicFolderLicenses
        BitTitanRelevance = "Public Folder licenses"
    }

    [PSCustomObject]@{
        Category = "Windows Entra Devices"
        Count = $WindowsDevices.Count
        BitTitanRelevance = "Alleen relevant indien Migration Agent wordt gebruikt"
    }
)

Export-InventoryCsv $Summary "00_BitTitan_License_Summary.csv"

# ============================================================
# Klaar
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Inventarisatie voltooid" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Output:" -ForegroundColor Cyan
Write-Host $OutputFolder -ForegroundColor White
Write-Host ""

$Summary | Format-Table -AutoSize

Write-Host ""
Write-Host "Verbindingen verbreken..." -ForegroundColor DarkGray

Disconnect-ExchangeOnline -Confirm:$false
Disconnect-MgGraph | Out-Null

Write-Host ""
Write-Host "Klaar." -ForegroundColor Green
