<#
.AUTHOR: Julian Mooren (citrixguyblog.com)
.DATE: 29.01.2026 
.NOTES:         
#>

# =========================
# CONFIGURATION
# =========================
$RegPath = "HKLM:\SOFTWARE\AVD\AVDPagefileSetup"
$MaxRebootAttempts = 3
$LogFile = "C:\Windows\Temp\AVDPagefileSetup\avd_nvme_pagefile.log"
$AvdServices = @("RDAgent", "RDAgentBootLoader")

# Pagefile options
$UseManagedPagefile = $true       # $true = system-managed, $false = fixed size
$FixedInitialSizeMB = 16384       # Only used if fixed size
$FixedMaxSizeMB = 32768

# =========================
# LOG FUNCTION
# =========================
function Write-Log {
    param (
        [string]$Message,
        [switch]$Error
    )
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $prefix = if ($Error) { "ERROR: " } else { "" }
    $entry = "[$ts] $prefix$Message"
    Write-Output $entry
    $folder = Split-Path $LogFile
    if (-not (Test-Path $folder)) { 
        New-Item -Path $folder -ItemType Directory -Force | Out-Null 
    }
    Add-Content $LogFile $entry -ErrorAction SilentlyContinue
}

# =========================
# INIT REGISTRY
# =========================
if (-not (Test-Path $RegPath)) { 
    New-Item -Path $RegPath -Force | Out-Null 
}

$Marker = (Get-ItemProperty -Path $RegPath -Name Marker -ErrorAction SilentlyContinue).Marker
$RebootCount = (Get-ItemProperty -Path $RegPath -Name RebootCount -ErrorAction SilentlyContinue).RebootCount
$ConfiguredDrive = (Get-ItemProperty -Path $RegPath -Name ConfiguredDrive -ErrorAction SilentlyContinue).ConfiguredDrive

if (-not $RebootCount) { $RebootCount = 0 }

Write-Log "=== Script Start === Marker: $Marker | RebootCount: $RebootCount"

# =========================
# CSE Check (Azure Custom Script Extension)
# =========================
$CseRegPath = "HKLM:\SOFTWARE\AVD\CSE"
$CseRegName = "CSECompleted"

Write-Log "Checking '$($CseRegName)' registry value existence..."

if (-not (Get-ItemProperty -Path $CseRegPath -Name $CseRegName -ErrorAction SilentlyContinue)) {
    Write-Log "'$($CseRegName)' registry value does not exist. Exiting."
    exit 0
}

Write-Log "'$($CseRegName)' registry value exists."

# =========================
# REBOOT LOOP PROTECTION - Check limit before doing work
# =========================
if ($RebootCount -ge $MaxRebootAttempts) {
    Write-Log "FATAL: Exceeded $MaxRebootAttempts reboot attempts. Aborting to prevent infinite loop." -Error
    
    # Try to restore AVD services before exiting
    foreach ($svc in $AvdServices) {
        try {
            Start-Service $svc -ErrorAction SilentlyContinue
            Write-Log "Attempted to start service $svc"
        }
        catch {}
    }
    exit 1
}

# =========================
# CHECK CURRENT PAGEFILE STATE
# =========================
$Pagefile = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
$PagefileOnD = $Pagefile | Where-Object { $_.Name -like "D:*" }
$PagefileOnC = $Pagefile | Where-Object { $_.Name -like "C:*" }

Write-Log "Current pagefile state: D: $(if($PagefileOnD){'EXISTS'}else{'NONE'}) | C: $(if($PagefileOnC){'EXISTS'}else{'NONE'})"

# =========================
# QUICK CHECK: Everything already perfect?
# =========================
$dDriveExists = Test-Path "D:\" -ErrorAction SilentlyContinue
$cDriveExists = Test-Path "C:\" -ErrorAction SilentlyContinue

# Check for temp disk availability
$TempDiskAvailable = Get-Disk | Where-Object {
    $_.OperationalStatus -eq "Online" -and
    $_.BusType -ne "File" -and
    (
        $_.FriendlyName -eq "Microsoft NVMe Direct Disk v2" -or # V6 SKU
        ($_.FriendlyName -eq "Msft Virtual Disk" -and $_.PartitionStyle -eq "MBR")  # V5 SKU
    )
}

$everythingPerfect = $false

# Scenario 1: D: drive available with pagefile configured
if ($TempDiskAvailable -and $dDriveExists -and $PagefileOnD) {
    Write-Log "D: drive with temp disk detected and pagefile is configured"
    $everythingPerfect = $true
}
# Scenario 2: No temp disk, C: drive pagefile is configured
elseif (-not $TempDiskAvailable -and $PagefileOnC) {
    Write-Log "No temp disk available, C: drive pagefile is configured - correct fallback state"
    $everythingPerfect = $true
}
else {
    # Log why configuration is needed
    if ($TempDiskAvailable -and -not $dDriveExists) {
        Write-Log "Configuration needed: Temp disk available but D: drive not initialized"
    }
    elseif ($TempDiskAvailable -and $dDriveExists -and -not $PagefileOnD) {
        Write-Log "Configuration needed: D: drive exists but pagefile not configured"
    }
    elseif ($TempDiskAvailable -and -not $PagefileOnD) {
        Write-Log "Configuration needed: Temp disk available but pagefile not on D:"
    }
    elseif (-not $TempDiskAvailable -and -not $PagefileOnC) {
        Write-Log "Configuration needed: No temp disk and pagefile not configured on C:"
    }
    else {
        Write-Log "Configuration needed: Current state does not match optimal configuration"
    }
}

if ($everythingPerfect) {
    Write-Log "Pagefile configuration is already optimal. Ensuring services are running."
    
    foreach ($svc in $AvdServices) {
        try {
            $service = Get-Service $svc -ErrorAction SilentlyContinue
            if ($service -and $service.Status -ne "Running") {
                Start-Service $svc -ErrorAction Stop
                Write-Log "Started service $svc"
            }
            else {
                Write-Log "Service $svc already running"
            }
        }
        catch {
            Write-Log "Failed to start service ${svc}: $_" -Error
        }
    }
    
    # Cleanup any stale registry markers
    Remove-ItemProperty -Path $RegPath -Name Marker, RebootCount, ConfiguredDrive, IntendedPageFile -ErrorAction SilentlyContinue

    Write-Log "=== Setup Complete === AVD Session Host ready for connections"
    exit 0
}

# =========================
# STOP AVD SERVICES 
# =========================
# Configuration is needed, stop services to prevent race condition
foreach ($svc in $AvdServices) {
    try {
        $service = Get-Service $svc -ErrorAction SilentlyContinue
        if ($service -and $service.Status -ne "Stopped") {
            Stop-Service $service.Name -Force -ErrorAction Stop
            Set-Service $service.Name -StartupType Manual -ErrorAction Stop
            Write-Log "Stopped $svc and set startup to Manual"
        }
    }
    catch {
        Write-Log "Failed to stop service ${svc}: $_" -Error
    }
}

# =========================
# DETECT VM DEALLOCATION / DISK WIPE
# =========================
# If configured for D: but D: drive doesn't exist, temp disk was wiped
if ($ConfiguredDrive -eq "D:" -and $Marker -eq 1) {
    $dDriveAccessible = Test-Path "D:\" -ErrorAction SilentlyContinue
    
    if (-not $dDriveAccessible) {
        Write-Log "WARNING: D: drive was configured but is not accessible."
        Write-Log "Temp disk likely wiped after VM deallocation. Resetting configuration."
        
        # Reset all markers to force reconfiguration
        Remove-ItemProperty -Path $RegPath -Name Marker, RebootCount, ConfiguredDrive, IntendedPageFile -ErrorAction SilentlyContinue
        $Marker = $null
        $RebootCount = 0
        $ConfiguredDrive = $null
        
        Write-Log "Configuration reset. Will reinitialize temp disk and pagefile."
    }
}

# =========================
# POST-REBOOT FINALIZATION CHECK
# =========================
if ($Marker -eq 1) {
    $expectedDrive = if ($ConfiguredDrive) { $ConfiguredDrive } else { "C:" }
    $pagefileActive = if ($expectedDrive -eq "D:") { $PagefileOnD } else { $PagefileOnC }
    
    if ($pagefileActive) {
        Write-Log "Pagefile already active on $expectedDrive. Finalizing setup."
        
        # Ensure AVD services are running (keep Manual startup type)
        foreach ($svc in $AvdServices) {
            try {
                $service = Get-Service $svc -ErrorAction SilentlyContinue
                if ($service) {
                    if ($service.Status -ne "Running") {
                        Start-Service $svc -ErrorAction Stop
                        Write-Log "Started service $svc"
                    }
                    else {
                        Write-Log "Service $svc already running"
                    }
                }
            }
            catch {
                Write-Log "Failed to start service ${svc}: $_" -Error
            }
        }
        
        # Cleanup registry
        Remove-ItemProperty -Path $RegPath -Name Marker, RebootCount, ConfiguredDrive, IntendedPageFile -ErrorAction SilentlyContinue
        Write-Log "=== Setup Complete === AVD Session Host ready for connections"
        exit 0
    }
    else {
        Write-Log "Marker set but pagefile not yet active on $expectedDrive. Continuing configuration."
    }
}

# =========================
# TEMP DISK DETECTION & INIT
# =========================
$PagefileDrive = "C:"  # default fallback
try {
    # Remove D: from CD-ROM if exists
    $cdromD = Get-Volume -DriveLetter D -ErrorAction SilentlyContinue | Where-Object DriveType -eq "CD-ROM"
    if ($cdromD) {
        Write-Log "CD-ROM detected on D:, removing drive letter"
        try {
            $drive = Get-WmiObject -Class Win32_Volume -Filter "DriveLetter='D:'"
            $drive.DriveLetter = $null
            $drive.Put() | Out-Null
            Write-Log "Removed D: from CD-ROM"
            Start-Sleep -Seconds 2
        }
        catch {
            Write-Log "Failed to remove D: from CD-ROM: $_" -Error
        }
    }

    # Check if temp disk is already initialized and formatted	
    $DVolume = Get-Volume -DriveLetter D -ErrorAction SilentlyContinue | Where-Object {
        $_.FileSystemType -eq "NTFS" -and 
        ($_.FileSystemLabel -eq "TempDisk" -or $_.FileSystemLabel -eq "Temporary Storage")
    }
	

    if ($DVolume) {
        Write-Log "Temp disk D: already initialized and formatted"
        $PagefileDrive = "D:"
    }
    else {
        # Find RAW NVMe temp disk
        $TempDisk = Get-Disk | Where-Object {
            $_.OperationalStatus -eq "Online" -and
            $_.BusType -ne "File" -and
            (
                $_.FriendlyName -eq "Microsoft NVMe Direct Disk v2" -or # V6 SKU
                ($_.FriendlyName -eq "Msft Virtual Disk" -and $_.PartitionStyle -eq "MBR")  # V5 SKU
            )
        }
		
        if ($TempDisk) {
            Write-Log "Found temp disk: Disk $($TempDisk.Number)"
            
            if ($TempDisk.PartitionStyle -eq "RAW") {
                Write-Log "Initializing temp disk as GPT"
                Initialize-Disk -Number $TempDisk.Number -PartitionStyle GPT -ErrorAction Stop | Out-Null
            }
            
            # Check if partition exists
            $existingPartition = Get-Partition -DiskNumber $TempDisk.Number -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter -eq 'D' }
            
            if (-not $existingPartition) {
                Write-Log "Creating partition and formatting as D:"
                New-Partition -DiskNumber $TempDisk.Number -UseMaximumSize -DriveLetter D -ErrorAction Stop | Out-Null
                Format-Volume -DriveLetter D -FileSystem NTFS -NewFileSystemLabel TempDisk -Confirm:$false -ErrorAction Stop | Out-Null
                Write-Log "Temp disk initialized and formatted as D:"
            }
            
            # Verify D: is accessible
            if (Test-Path "D:\") {
                $PagefileDrive = "D:"
                Write-Log "D: drive verified and accessible"
            }
            else {
                throw "D: drive not accessible after configuration"
            }
        }
        else {
            Write-Log "No temp disk detected. Using fallback pagefile on C:"
        }
    }
}
catch {
    Write-Log "Temp disk initialization failed: $_" -Error
    $PagefileDrive = "C:"
}

# =========================
# PAGEFILE CONFIGURATION
# =========================
$needsConfiguration = $false
$needsReboot = $false

# Verify the target drive actually exists and is accessible
$targetDriveExists = Test-Path "${PagefileDrive}\"
Write-Log "Target drive ${PagefileDrive} exists: $targetDriveExists"

if ($PagefileDrive -eq "D:") {
    # For D: drive, verify pagefile is configured AND the drive exists AND pagefile file exists
    $pagefileFileExists = Test-Path "D:\pagefile.sys" -ErrorAction SilentlyContinue
    Write-Log "Pagefile file on D: exists: $pagefileFileExists"
    
    if ($PagefileOnD -and $targetDriveExists -and $pagefileFileExists) {
        # Everything is already perfect on D:
        $needsConfiguration = $false
        $needsReboot = $false
    }
    else {
        # Need to configure D: pagefile
        $needsConfiguration = $true
        $needsReboot = $true
    }
}
else {
    # For C: drive, check if configured
    $needsConfiguration = -not $PagefileOnC
    
    # If we're switching FROM D: TO C: (fallback scenario because D: disappeared), we need a reboot
    if ($ConfiguredDrive -eq "D:") {
        Write-Log "Detected switch from D: to C: drive (D: no longer available, falling back)"
        $needsConfiguration = $true
        $needsReboot = $true
    }
    else {
        $needsReboot = $false  # C: drive usually doesn't need reboot if already on C:
    }
}

Write-Log "Configuration needed: $needsConfiguration | Reboot needed: $needsReboot"

# If no configuration needed, finalize and exit
if (-not $needsConfiguration) {
    Write-Log "Pagefile already correctly configured on $PagefileDrive. Finalizing setup."
    
    # Start services and cleanup
    foreach ($svc in $AvdServices) {
        try {
            $service = Get-Service $svc -ErrorAction SilentlyContinue
            if ($service -and $service.Status -ne "Running") {
                Start-Service $svc -ErrorAction Stop
                Write-Log "Started service $svc"
            }
        }
        catch {
            Write-Log "Failed to start service ${svc}: $_" -Error
        }
    }
    
    Remove-ItemProperty -Path $RegPath -Name Marker, RebootCount, ConfiguredDrive, IntendedPageFile -ErrorAction SilentlyContinue
    Write-Log "=== Setup Complete === AVD Session Host ready"
    exit 0
}

# =========================
# APPLY PAGEFILE CONFIGURATION
# =========================
try {
    Write-Log "Configuring pagefile on $PagefileDrive"
    
    # Store what we're about to configure
    $intendedConfig = if ($UseManagedPagefile) {
        "$PagefileDrive\pagefile.sys 0 0 (system-managed)"
    }
    else {
        "$PagefileDrive\pagefile.sys $FixedInitialSizeMB $FixedMaxSizeMB (fixed)"
    }
    Set-ItemProperty -Path $RegPath -Name IntendedPageFile -Value $intendedConfig -Force
    
    # Remove existing pagefiles first
    $existingPagefiles = Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue
    if ($existingPagefiles) {
        foreach ($pf in $existingPagefiles) {
            Remove-CimInstance -InputObject $pf -ErrorAction SilentlyContinue
            Write-Log "Removed existing pagefile WMI entry: $($pf.Name)"
        }
    }
    
    if ($UseManagedPagefile) {
        $pfValue = "$PagefileDrive\pagefile.sys 0 0"
        Write-Log "Setting system-managed pagefile on $PagefileDrive"
    }
    else {
        $pfValue = "$PagefileDrive\pagefile.sys $FixedInitialSizeMB $FixedMaxSizeMB"
        Write-Log "Setting fixed pagefile on $PagefileDrive (${FixedInitialSizeMB}MB initial, ${FixedMaxSizeMB}MB max)"
    }

    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" `
        -Name "PagingFiles" -Value $pfValue -Type MultiString -Force -ErrorAction Stop

    # Set marker and configured drive
    Set-ItemProperty -Path $RegPath -Name Marker -Value 1 -Force
    Set-ItemProperty -Path $RegPath -Name ConfiguredDrive -Value $PagefileDrive -Force

    Write-Log "Pagefile registry updated successfully"

    # Increment reboot counter only when actually rebooting
    if ($needsReboot) {
        $RebootCount++
        Set-ItemProperty -Path $RegPath -Name RebootCount -Value $RebootCount -Force
        Write-Log "Reboot attempt #$RebootCount of $MaxRebootAttempts"
        
        Write-Log "Initiating system reboot to activate pagefile on $PagefileDrive"
        Start-Sleep -Seconds 2
        Restart-Computer -Force
        
        # Script will exit here due to reboot
        exit 0
    }
    else {
        Write-Log "Pagefile configured on $PagefileDrive. No reboot required."
        
        # Start services immediately since no reboot needed
        foreach ($svc in $AvdServices) {
            try {
                $service = Get-Service $svc -ErrorAction SilentlyContinue
                if ($service -and $service.Status -ne "Running") {
                    Start-Service $svc -ErrorAction Stop
                    Write-Log "Started service $svc"
                }
            }
            catch {
                Write-Log "Failed to start service ${svc}: $_" -Error
            }
        }
        
        Remove-ItemProperty -Path $RegPath -Name Marker, RebootCount, ConfiguredDrive, IntendedPageFile -ErrorAction SilentlyContinue
        Write-Log "=== Setup Complete === AVD Session Host ready"
        exit 0
    }
}
catch {
    Write-Log "Failed to configure pagefile: $_" -Error
    
    # Try to restore services before failing
    foreach ($svc in $AvdServices) {
        try {
            Start-Service $svc -ErrorAction SilentlyContinue
            Write-Log "Started service $svc"
        }
        catch {}
    }
    exit 1
}