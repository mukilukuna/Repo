# Script: SCR_UPD_UPDATEWITHOUTREBOOT.ps1
# Purpose: SCR UPD UPDATEWITHOUTREBOOT

# Controleer en installeer vereiste modules
foreach ($module in @('PSWindowsUpdate')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

Set-ExecutionPolicy Bypass -Confirm:$false
Get-WindowsUpdate -AcceptAll -ForceInstall -Install
# # Update geschiedenis ophalen
# Install-Module -Name PUDAdminCenterPrototype -allowclobber
# Import-Module PUDAdminCenterPrototype
# Get-WuaHistory | select-object Result, Product, Date, title | out-file -filepath c:\temp\Updatehystory.txt