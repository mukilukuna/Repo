[CmdletBinding()]
param (
    [string]$ExportDirectory
)

. (Join-Path $PSScriptRoot '..\..\Common\ExportPath.ps1')
$ExportDirectory = Resolve-ExportDirectory -Path $ExportDirectory -DefaultPath 'C:\temp' -Prompt 'Exportmap voor het public-folderrapport'
$OutputPath = Join-Path -Path $ExportDirectory -ChildPath 'PublicFolderPermissions.csv'

# Script: Office365_PublicFolders_GetPermissions.ps1
# Purpose: Office365 PublicFolders GetPermissions

# Controleer en installeer vereiste modules
foreach ($module in @('ExchangeOnlineManagement')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

Connect-ExchangeOnline
#SMTP Adresses
Get-MailPublicFolder | ft Alias, PrimarySmtpAddress

#Permissions
$Result=@()
$allFolders = Get-PublicFolder -Recurse -ResultSize Unlimited
$totalfolders = $allFolders.Count
$i = 1 
$allFolders | ForEach-Object {
$folder = $_
Write-Progress -activity "Processing $folder" -status "$i out of $totalfolders completed"
$folderPerms = Get-PublicFolderClientPermission -Identity $folder.Identity
$folderPerms | ForEach-Object {
$Result += New-Object PSObject -property @{ 
Folder = $folder.Identity
User = $_.User
Permissions = $_.AccessRights
}}
$i++
}
$Result | Select Folder, User, Permissions |
Export-CSV -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Resultaten geëxporteerd naar: $OutputPath" -ForegroundColor Green
