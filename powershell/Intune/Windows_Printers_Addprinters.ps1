# Script: Windows_Printers_Addprinters.ps1
# Purpose: Windows Printers Addprinters
$ErrorActionPreference = 'SilentlyContinue'

Add-printerport -Name "TCPPort:10.0.0.2" -PrinterHostAddress "10.0.0.2"
Add-printerport -Name "TCPPort:10.0.0.3" -PrinterHostAddress "10.0.0.3"
Add-printerport -Name "TCPPort:10.0.0.4" -PrinterHostAddress "10.0.0.4"
Add-printerport -Name "TCPPort:10.0.0.5" -PrinterHostAddress "10.0.0.5"
Add-printerport -Name "TCPPort:10.0.0.6" -PrinterHostAddress "10.0.0.6"

Add-PrinterDriver -Name "RICOH MP C3004 PCL 5c"
Add-PrinterDriver -Name "RICOH MP C3004ex PCL 5c"
Add-PrinterDriver -Name "Dell B2375dnf Mono MFP XPS"

Add-Printer -Name "1e - Directie" -PortName "TCPPort:10.0.0.2" -DriverName "RICOH MP C3004 PCL 5c"
Add-Printer -Name "BG - Kamer Frank" -PortName "TCPPort:10.0.0.3" -DriverName "RICOH MP C3004ex PCL 5c"
Add-Printer -Name "BG - P&O" -PortName "TCPPort:10.0.0.4" -DriverName "RICOH MP C3004 PCL 5c"
Add-Printer -Name "1e - Managers" -PortName "TCPPort:10.0.0.5" -DriverName "RICOH MP C3004ex PCL 5c"
Add-Printer -Name "BG - Dell ZW" -PortName "TCPPort:10.0.0.6" -DriverName "Dell B2375dnf Mono MFP XPS"


