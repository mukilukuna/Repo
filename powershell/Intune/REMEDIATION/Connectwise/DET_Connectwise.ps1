# Script: DET_ConnectWiseAutomateRemoteAgentInstalled.ps1
# Purpose: Detect ConnectWise Automate Remote Agent (ConnectWise Inc.)

$displayName = 'ConnectWise Automate Remote Agent'
$vendorMatch = 'ConnectWise Inc.'

$paths = @(
    'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'Registry::HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$found = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
    Where-Object {
        $_.DisplayName -eq $displayName -and
        (
            $_.Publisher -eq $vendorMatch -or
            $_.Publisher -like "*$vendorMatch*"
        )
    } |
    Select-Object -First 1

if ($found) {
    Write-Host "ConnectWise Automate Remote Agent is installed"
    exit 1
} else {
    Write-Host "ConnectWise Automate Remote Agent isn't installed"
    exit 0
}
