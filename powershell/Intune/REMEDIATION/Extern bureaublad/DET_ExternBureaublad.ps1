# Script: DET_ExternBureaubladInstalled.ps1
# Purpose: Detect Extern bureaublad (Microsoft Corporation)

$displayName = 'Extern bureaublad'
$vendorMatch = 'Microsoft Corporation'

$paths = @(
    'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'Registry::HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$found = Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
    Where-Object {
        $_.DisplayName -eq $displayName -and
        ($_.Publisher -eq $vendorMatch -or $_.Publisher -like "*$vendorMatch*")
    } |
    Select-Object -First 1

if ($found) {
    Write-Host "Extern bureaublad is installed"
    exit 1
} else {
    Write-Host "Extern bureaublad isn't installed"
    exit 0
}
