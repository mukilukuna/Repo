# Script: DET_PulsewayInstalled.ps1
# Purpose: Detect Pulseway (MMSOFT Design)

$displayName = 'Pulseway'
$vendorMatch = 'MMSOFT Design'

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
    Write-Host "Pulseway is installed"
    exit 1
} else {
    Write-Host "Pulseway isn't installed"
    exit 0
}
