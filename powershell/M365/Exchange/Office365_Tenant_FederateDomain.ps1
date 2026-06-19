# Controleer en installeer vereiste modules
foreach ($module in @('MSOnline')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

#Kill federation sync - AD Sync
Connect-MsolService
Get-MsolCompanyInformation | fl *synch*

#Federation
Set-MsolDomainAuthentication -DomainName example.org -Authentication Managed


#AD Sync
(Get-MSOLCompanyInformation).DirectorySynchronizationEnabled
Set-MsolDirSyncEnabled -EnableDirSync $false
