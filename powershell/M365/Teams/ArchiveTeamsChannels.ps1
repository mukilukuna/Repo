# Controleer en installeer vereiste modules
foreach ($module in @('Microsoft.Graph')) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        Write-Host "Module '$module' wordt geïnstalleerd..." -ForegroundColor Yellow
        Install-Module -Name $module -Force -AllowClobber -Scope CurrentUser
    }
    Import-Module -Name $module -ErrorAction Stop
}

# Variables
$teamId = ""  # Your Team ID

# Connect to Microsoft Graph with the required permissions
Connect-MgGraph -Scopes "ChannelSettings.ReadWrite.All"

# Get all channels in the team
$channels = Get-TeamChannel -GroupId $teamId

# Loop through each channel and archive it
foreach ($channel in $channels) {
    $channelId = $channel.Id
    try {
        # Archive the channel
        Invoke-MgBetaArchiveTeamChannel -TeamId $teamId -ChannelId $channelId -ShouldSetSpoSiteReadOnlyForMembers
        Write-Host "Successfully archived channel: $($channel.DisplayName)"
    } catch {
        Write-Host "Failed to archive channel: $($channel.DisplayName) - $_"
    }
}

# Disconnect from Microsoft Graph
Disconnect-MgGraph
