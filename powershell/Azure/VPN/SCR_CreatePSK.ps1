$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
$psk = [Convert]::ToBase64String($bytes)
$psk


