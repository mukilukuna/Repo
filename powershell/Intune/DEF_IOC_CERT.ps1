[CmdletBinding()]
param (
    [string]$ExportDirectory
)

. (Join-Path $PSScriptRoot '..\Common\ExportPath.ps1')
$ExportDirectory = Resolve-ExportDirectory -Path $ExportDirectory -DefaultPath 'C:\temp' -Prompt 'Exportmap voor het certificaat'

# Pad van het geblokkeerde bestand (uit de alert)
$path = "C:\Users\MukiLukunaITSynergy\Downloads\UniLogicSetup_1_41_Build_213.exe"

$sig  = Get-AuthenticodeSignature -FilePath $path
$cert = $sig.SignerCertificate              # leaf cert
$dest = Join-Path -Path $ExportDirectory -ChildPath 'UniLogicSetup_1_41_Build_213.cer'
Export-Certificate -Cert $cert -FilePath $dest | Out-Null
Write-Host "Certificaat geëxporteerd naar: $dest" -ForegroundColor Green
$cert.Thumbprint
