# Controleer en installeer vereiste modules
foreach ($module in @('Microsoft.Online.SharePoint.PowerShell')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

Connect-SPOService -Url 


$label = Get-Label -Identity "Sensitive Information" | Select-Object Name, GUID
$labelGuid = $label.GUID

# Define the URLs of the SharePoint sites
$sites = @(
    "",
    "",
    ""
)

# Loop through each site and apply the sensitivity label
foreach ($siteUrl in $sites) {
    Set-SPOSite -Identity $siteUrl -SensitivityLabel $labelGuid
    Write-Host "Applied sensitivity label to $siteUrl"
}
