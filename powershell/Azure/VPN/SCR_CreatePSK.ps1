# Script: New-SimplePSK.ps1
# Purpose: Genereer een random Base64 PSK

$ByteLength = 32
$bytes = New-Object byte[] $ByteLength
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$psk = [Convert]::ToBase64String($bytes)

Write-Host ''
Write-Host 'Gegenereerde PSK:' -ForegroundColor Cyan
Write-Host $psk -ForegroundColor Green
Write-Host ''

Set-Clipboard -Value $psk
Write-Host 'De PSK is naar het klembord gekopieerd.' -ForegroundColor Yellow