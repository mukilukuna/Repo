$productCode = (Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq 'Extern bureaublad' -and $_.Vendor -eq 'Microsoft Corporation' }).IdentifyingNumber

msiexec /x $productCode /qn REBOOT="ReallySuppress"