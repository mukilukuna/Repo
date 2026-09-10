# HP Intune Cleanup 1.0 - 2026-09-08
# Windows PowerShell 5.1 / PowerShell 7 on Windows. No module installation.
# Scope: the nine machine-wide desktop apps shown in the supplied screenshot.
<#
Run as SYSTEM through Intune, or as local administrator for a pilot.
Default: remove HP Wolf Security, its Console, and HP Security Update Service.
-AuditOnly produces a read-only plan on stdout; does not create logs or uninstall.
-WhatIf is equivalent for planning. No firmware changes or forced removal.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param([switch]$AuditOnly)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
# POLICY: keep this block identical in Remove and Detect.
# Exact application names only. Change a value to $true to select that app.
# Evaluate Sure Run / Sure Recover provisioning and HP service use first.
$AppPolicy = [ordered]@{
    'HP Sure Run Module'         = $false
    'HP Sure Recover'            = $false
    'HP Wolf Security'           = $true
    'HP Wolf Security - Console' = $true
    'HP Security Update Service' = $true
    'HP Connection Optimizer'    = $false
    'HP Documentation'           = $false
    'HP Notifications'           = $false
    'HP One Agent'               = $false
}

function Test-HPPublisher {
    param([string]$Publisher)
    return $Publisher.Trim() -match '^(HP( Inc\.?)?|HP Development Company, L\.P\.|Hewlett-Packard( Company)?)$'
}

function Get-MachineApps {
    # Explicit registry views work from both 32-bit and 64-bit PowerShell.
    # Do not query Win32_Product: that can initiate MSI consistency checks.
    $views = @([Microsoft.Win32.RegistryView]::Registry32)
    if ([Environment]::Is64BitOperatingSystem) {
        $views = @([Microsoft.Win32.RegistryView]::Registry64,
                   [Microsoft.Win32.RegistryView]::Registry32)
    }
    foreach ($view in $views) {
        $base = $null
        $uninstall = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $uninstall = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if ($null -eq $uninstall) { throw "Uninstall registry unavailable: $view" }
            foreach ($keyName in $uninstall.GetSubKeyNames()) {
                $key = $null
                try {
                    $key = $uninstall.OpenSubKey($keyName)
                    if ($null -eq $key) { throw "Registry changed during inventory: $keyName" }
                    $name = ([string]$key.GetValue('DisplayName', '')).Trim()
                    if ([string]::IsNullOrWhiteSpace($name)) { continue }
                    [pscustomobject]@{
                        DisplayName = $name
                        DisplayVersion = [string]$key.GetValue('DisplayVersion', '')
                        Publisher = ([string]$key.GetValue('Publisher', '')).Trim()
                        RegistryView = [string]$view
                        KeyName = $keyName
                        WindowsInstaller = [int]$key.GetValue('WindowsInstaller', 0)
                        UninstallString = [string]$key.GetValue('UninstallString', '')
                        QuietUninstallString = [string]$key.GetValue('QuietUninstallString', '')
                        InstallLocation = [string]$key.GetValue('InstallLocation', '')
                        SystemComponent = [int]$key.GetValue('SystemComponent', 0)
                    }
                } finally {
                    if ($null -ne $key) { $key.Dispose() }
                }
            }
        } finally {
            if ($null -ne $uninstall) { $uninstall.Dispose() }
            if ($null -ne $base) { $base.Dispose() }
        }
    }
}

function Get-MsiProductCode {
    param($App)
    $guid = '\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}'
    # A GUID-shaped key alone is not proof of MSI (EXE bundles also use GUIDs).
    if ($App.WindowsInstaller -eq 1 -and $App.KeyName -match "^$guid`$") {
        return $App.KeyName
    }
    # Accept only an actual msiexec command, not a GUID in an arbitrary command.
    $pattern = '(?i)^\s*"?(?:[A-Z]:\\[^"\r\n]*\\)?msiexec(?:\.exe)?"?\s+/(?:I|X)\s*(?<Code>' + $guid + ')(?:\s|$)'
    foreach ($command in @($App.UninstallString, $App.QuietUninstallString)) {
        if ($command -match $pattern) { return $Matches['Code'] }
    }
    return $null
}

function Get-UninstallPlan {
    param($App)
    if (-not (Test-HPPublisher $App.Publisher)) {
        throw "Unexpected or missing publisher for $($App.DisplayName): '$($App.Publisher)'"
    }
    $code = Get-MsiProductCode $App
    if ($code) {
        return [pscustomobject]@{ Kind = 'MSI'; ProductCode = $code; FilePath = ''; Arguments = '' }
    }
    # Only use a vendor-registered quiet command. Never guess /S or /silent.
    $command = [Environment]::ExpandEnvironmentVariables($App.QuietUninstallString).Trim()
    if ([string]::IsNullOrWhiteSpace($command)) {
        throw "No verified silent uninstall method for $($App.DisplayName); inspect inventory."
    }
    $file = ''
    $arguments = ''
    if ($command -match '^"(?<File>[^"\r\n]+\.exe)"\s+(?<Args>.+)$') {
        $file = $Matches['File']; $arguments = $Matches['Args']
    } elseif ($command -match '^(?<File>[^\s"]+\.exe)\s+(?<Args>.+)$') {
        $file = $Matches['File']; $arguments = $Matches['Args']
    } else { throw "Unsupported quiet command format for $($App.DisplayName)." }
    if ($file -notmatch '^[A-Za-z]:\\' -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Quiet uninstaller missing or not an absolute local path: $file"
    }
    # Require explicit suppression of reboots in the registered EXE command.
    if ($arguments -notmatch '(?i)(?:^|\s)(?:/norestart|/noreboot|REBOOT="?ReallySuppress"?)(?:\s|$)') {
        throw "EXE quiet command has no explicit reboot suppression for $($App.DisplayName); review vendor method."
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $file
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch '(?i)(?:^|,\s*)(?:CN|O)="?(?:HP Inc\.?|HP Development Company, L\.P\.|Hewlett-Packard Company)"?(?:,|$)') {
        throw "Quiet uninstaller has no valid HP signature: $file"
    }
    return [pscustomobject]@{ Kind = 'EXE'; ProductCode = ''; FilePath = $file; Arguments = $arguments }
}

function Write-CleanupLog {
    param([string]$Message)
    Add-Content -LiteralPath $script:LogFile -Encoding UTF8 -Value (
        '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

$script:LogFile = $null
try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'This script requires Windows.'
    }
    $selected = @($AppPolicy.Keys | Where-Object { $AppPolicy[$_] })
    $allApps = @(Get-MachineApps)
    $targets = @($allApps | Where-Object { $selected -contains $_.DisplayName })
    if ($AuditOnly -or $WhatIfPreference) {
        foreach ($name in $AppPolicy.Keys) {
            $entries = @($allApps | Where-Object { $_.DisplayName -eq $name })
            if ($entries.Count -eq 0) {
                Write-Output "ABSENT | $name | Selected=$($AppPolicy[$name])"
                continue
            }
            foreach ($app in $entries) {
                $method = 'Not selected'
                if ($AppPolicy[$name]) {
                    try { $method = (Get-UninstallPlan $app).Kind }
                    catch { $method = 'BLOCKED: ' + $_.Exception.Message }
                }
                Write-Output "$name | $($app.DisplayVersion) | $($app.RegistryView) | Selected=$($AppPolicy[$name]) | $method"
            }
        }
        exit 0
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run as SYSTEM or as an elevated administrator.'
    }
    $logRoot = Join-Path $env:ProgramData 'HPAppCleanup'
    if (-not (Test-Path -LiteralPath $logRoot)) {
        New-Item -Path $logRoot -ItemType Directory | Out-Null
    }
    # SYSTEM and Administrators only: logs include machine uninstall information.
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sidText in @('S-1-5-18', 'S-1-5-32-544')) {
        $sid = [Security.Principal.SecurityIdentifier]::new($sidText)
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $logRoot -AclObject $acl
    $runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $script:LogFile = Join-Path $logRoot "cleanup-$runId.log"
    Write-CleanupLog ('Selected apps: ' + ($selected -join '; '))
    $allApps | Where-Object { (Test-HPPublisher $_.Publisher) -or ($AppPolicy.Keys -contains $_.DisplayName) } |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $logRoot "inventory-$runId.json") -Encoding UTF8
    # Resolve ALL selected methods before removing anything. An unsupported
    # optional package must not result in a misleading partial cleanup.
    foreach ($app in $targets) { $null = Get-UninstallPlan $app }
    $rebootRequired = $false
    $deadline = (Get-Date).AddMinutes(24)
    $msiexec = Join-Path $env:WINDIR 'System32\msiexec.exe'
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $msiexec = Join-Path $env:WINDIR 'Sysnative\msiexec.exe'
    }
    # Policy order: optional Sure Run / Recover first; Wolf -> Console -> Update.
    foreach ($name in $selected) {
        # Re-read: a bundle may already have removed another registered component.
        $entries = @(Get-MachineApps | Where-Object { $_.DisplayName -eq $name })
        foreach ($app in $entries) {
            $current = @(Get-MachineApps | Where-Object {
                $_.RegistryView -eq $app.RegistryView -and $_.KeyName -eq $app.KeyName
            })
            if ($current.Count -eq 0) { continue }
            $app = $current[0]
            $plan = Get-UninstallPlan $app
            if (-not $PSCmdlet.ShouldProcess($app.DisplayName, 'Uninstall application')) {
                throw "Removal was not approved for $($app.DisplayName)."
            }
            $seconds = [int][Math]::Min(600, [Math]::Floor(($deadline - (Get-Date)).TotalSeconds))
            if ($seconds -lt 15) { throw 'Time budget exhausted; remaining apps will be detected again.' }
            if ($plan.Kind -eq 'MSI') {
                $safeName = $app.DisplayName -replace '[^A-Za-z0-9-]', '_'
                $msiLog = Join-Path $logRoot ("MSI-$runId-$safeName-$($app.KeyName).log")
                $file = $msiexec
                $arguments = '/x {0} /qn /norestart REBOOT=ReallySuppress /L*v "{1}"' -f $plan.ProductCode, $msiLog
            } else {
                $file = $plan.FilePath
                $arguments = $plan.Arguments
            }
            Write-CleanupLog "Uninstalling $($app.DisplayName) $($app.DisplayVersion) via $($plan.Kind)"
            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $file
            $startInfo.Arguments = $arguments
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $process = [Diagnostics.Process]::new()
            $process.StartInfo = $startInfo
            try {
                if (-not $process.Start()) { throw "Could not start uninstaller for $name." }
                if (-not $process.WaitForExit($seconds * 1000)) {
                    # Dispose closes the handle; it does not kill the MSI transaction.
                    throw "Timeout for $name; process $($process.Id) may still run. Inspect before another attempt."
                }
                $result = $process.ExitCode
            } finally { $process.Dispose() }
            if ($null -eq $result) { throw "No uninstall exit code for $name." }
            Write-CleanupLog "Exit code $result for $name"
            if ($result -eq 3010) { $rebootRequired = $true }
            if ($plan.Kind -eq 'MSI') { $accepted = @(0, 1605, 1614, 3010) }
            else { $accepted = @(0, 3010) }
            if ($accepted -notcontains $result) {
                if ($result -eq 1618) { throw 'Windows Installer is busy (1618). Try at the next check-in.' }
                throw "Uninstall failed ($result) for $name. Check MSI/HP logs and any active removal protection."
            }
            $remainingEntry = @(Get-MachineApps | Where-Object {
                $_.RegistryView -eq $app.RegistryView -and $_.KeyName -eq $app.KeyName
            })
            if ($remainingEntry.Count -gt 0) {
                throw "Entry still present for $name. RebootRequested=$rebootRequired. Inspect logs before retry."
            }
        }
    }
    $remaining = @(Get-MachineApps | Where-Object { $selected -contains $_.DisplayName })
    if ($remaining.Count -gt 0) {
        throw ('Selected apps remain: ' + (($remaining.DisplayName | Sort-Object -Unique) -join ', '))
    }
    Write-CleanupLog "SUCCESS: selected registrations absent. RebootRequired=$rebootRequired"
    Write-Output "SUCCESS: selected HP apps absent. RebootRequired=$rebootRequired. Log=$script:LogFile"
    # Platform scripts / Remediations use 0 for success. Do not return 3010 here.
    # A reboot request is reported above; schedule the restart separately.
    exit 0
} catch {
    $message = $_.Exception.Message
    if ($script:LogFile) {
        try { Write-CleanupLog "ERROR: $message" } catch { }
    }
    if ($message.Length -gt 1200) { $message = $message.Substring(0, 1200) }
    Write-Output "ERROR: $message Log=$script:LogFile"
    exit 1
}
