[CmdletBinding()]
param (
    [string]$ExportDirectory
)

function Resolve-ExportDirectory {
    param (
        [string]$Path,
        [string]$DefaultPath = 'C:\temp'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Read-Host "Exportmap (druk op Enter voor '$DefaultPath')"
    }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $DefaultPath
    }

    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path -Path (Get-Location).ProviderPath -ChildPath $Path
    }

    $Path = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    elseif (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Het exportpad is geen map: $Path"
    }

    return $Path
}

$ExportDirectory = Resolve-ExportDirectory -Path $ExportDirectory

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
$OutputPath = Join-Path -Path $ExportDirectory -ChildPath 'AzureAD_Groepen.csv'
$resultsarray | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Delimiter ";" -Encoding UTF8

Write-Output "Resultaten geëxporteerd naar: $OutputPath"
