# Pad van het geblokkeerde bestand (uit de alert)
$path = "C:\Users\MukiLukunaITSynergy\Downloads\UniLogicSetup_1_41_Build_213.exe"

$sig  = Get-AuthenticodeSignature -FilePath $path
$cert = $sig.SignerCertificate              # leaf cert
$dest = "C:\Temp\UniLogicSetup_1_41_Build_213.cer"
Export-Certificate -Cert $cert -FilePath $dest | Out-Null
$cert.Thumbprint
