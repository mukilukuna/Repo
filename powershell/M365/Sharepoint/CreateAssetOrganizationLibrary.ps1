# Installeer de PnP PowerShell-module indien nodig
if (-not (Get-Module -Name PnP.PowerShell -ListAvailable)) {
    Install-Module -Name PnP.PowerShell -Force -AllowClobber
}

$AdminUrl = "https://org1-admin.sharepoint.com/"  # Vervang met de SharePoint Admin-URL
$SiteUrl = "https://org1.sharepoint.com/sites/OrganizationalAssets"  # De site waar je bibliotheken wilt aanmaken

Connect-PnPOnline -Url $SiteUrl -UseWebLogin

$libraryURL = @(
    "https://org1.sharepoint.com/sites/OrganizationalAssets/Org2",
    "https://org1.sharepoint.com/sites/OrganizationalAssets/Grootrotterdam",
    "https://org1.sharepoint.com/sites/OrganizationalAssets/Peuter&co",
    "https://org1.sharepoint.com/sites/OrganizationalAssets/JOZ",
    "https://org1.sharepoint.com/sites/OrganizationalAssets/SMWR",
    "https://org1.sharepoint.com/sites/OrganizationalAssets/Org1")
$cdnType = "Private"
$orgAssetType = "OfficeTemplateLibrary"

foreach ($library in $libraryURL) {
    try {
        Add-PnPOrgAssetsLibrary -LibraryUrl $library -OrgAssetType $orgAssetType -CdnType Private
    }
    catch {
        Write-Host "Error: $_"
    }
}
