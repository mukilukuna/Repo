#JVM delete all ADgroups from disabled OU#

# Controleer of de ActiveDirectory module beschikbaar is (onderdeel van RSAT)
if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
    Write-Warning "De ActiveDirectory module is niet gevonden. Installeer RSAT via: Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
    throw "ActiveDirectory module is vereist om dit script uit te voeren."
}
Import-Module -Name ActiveDirectory -ErrorAction Stop

$OU = "OU=2021,OU=Disabled,OU=Users,OU=HD Medi bv,DC=hdmedi,DC=eu"
$Users = Get-ADUser -SearchBase $OU -Filter *

Get-ADGroup -Filter * |
Remove-ADGroupMember -Members $users -Confirm:$False