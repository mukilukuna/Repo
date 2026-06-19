# Controleer en installeer vereiste modules
foreach ($module in @('Microsoft.Graph')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

# Verbinden met Microsoft Graph
Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All"

# Haal alle groepen op
$groups = Get-MgGroup -All

$resultsarray = @()

# Itereren over groepen en leden ophalen
foreach ($group in $groups) {
    Write-Output "Ophalen van leden voor groep: $($group.DisplayName)"
    
    try {
        $members = Get-MgGroupMember -GroupId $group.Id -All
        foreach ($member in $members) {
            $UserObject = [PSCustomObject]@{
                "Group Name"        = $group.DisplayName
                "Member Name"       = $member.DisplayName
                "ObjType"           = $member.ODataType
                "UserPrincipalName" = $member.UserPrincipalName
            }
            $resultsarray += $UserObject
        }
    }
    catch {
        Write-Output "Fout bij het ophalen van leden voor groep '$($group.DisplayName)': $_"
    }
}

# Exporteren naar CSV
$OutputPath = "C:\scripts\output.csv"
$resultsarray | Export-Csv -Path $OutputPath -NoTypeInformation -Delimiter ";" -Encoding UTF8

Write-Output "Resultaten geëxporteerd naar: $OutputPath"
