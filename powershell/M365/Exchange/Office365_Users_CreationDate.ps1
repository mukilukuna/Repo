[CmdletBinding()]
param (
    [string]$ExportDirectory
)

. (Join-Path $PSScriptRoot '..\..\Common\ExportPath.ps1')
$ExportDirectory = Resolve-ExportDirectory -Path $ExportDirectory -DefaultPath 'C:\temp' -Prompt 'Exportmap voor het aanmaakdatumrapport'
$OutputPath = Join-Path -Path $ExportDirectory -ChildPath 'AzureAD_Users_CreationDate.csv'

# Script: Office365_Users_CreationDate.ps1
# Purpose: Office365 Users CreationDate

# Controleer en installeer vereiste modules
foreach ($module in @('AzureAD')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

Connect-AzureAD 

$Report = @()
$AAD_users = Get-AzureADUser -All:$true
foreach ($AAD_User in $AAD_users) {
$objReport = [PSCustomObject]@{
User     = $AAD_User.UserPrincipalName
CreationDate  = (Get-AzureADUserExtension -ObjectId $AAD_User.ObjectId).Get_Item("createdDateTime")
}
$Report += $objReport
}
$Report

$Report | Export-CSV -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "Resultaten geëxporteerd naar: $OutputPath" -ForegroundColor Green
