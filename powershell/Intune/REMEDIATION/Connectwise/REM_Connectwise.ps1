$productCode = (Get-WmiObject -Class Win32_Product | Where-Object { $_.Name -eq 'ConnectWise Automate Remote Agent' -and $_.Vendor -eq 'ConnectWise Inc.' }).IdentifyingNumber
 
msiexec /x $productCode /qn REBOOT="ReallySuppress"