#Kill federation sync - AD Sync
Connect-MsolService
Get-MsolCompanyInformation | fl *synch*

#Federation
Set-MsolDomainAuthentication -DomainName example.org -Authentication Managed


#AD Sync
(Get-MSOLCompanyInformation).DirectorySynchronizationEnabled
Set-MsolDirSyncEnabled -EnableDirSync $false
