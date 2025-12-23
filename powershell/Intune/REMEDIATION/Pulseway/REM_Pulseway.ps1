# Script: REM_Pulseway.ps1
# Purpose: Remove Pulseway (MMSOFT Design) without Win32_Product
# Assumption: Detection already confirmed it's installed
# Logging: Transcript to IME log folder

$TranscriptPath = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$TranscriptName = "REM_Pulseway.log"
New-Item $TranscriptPath -ItemType Directory -Force | Out-Null

# stop orphaned transcripts
try { Stop-Transcript | Out-Null } catch [System.InvalidOperationException] {}

Start-Transcript -Path (Join-Path $TranscriptPath $TranscriptName) -Append | Out-Null

try {
    $displayName = 'Pulseway'
    $vendorMatch = 'MMSOFT Design'
    $msiLogFile  = Join-Path $env:TEMP "Pulseway_Uninstall_MSI.log"

    $uninstallPaths = @(
        'Registry::HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'Registry::HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    # Geen "is het geinstalleerd?" check; we halen alleen uninstall entries op om uit te voeren
    $apps = Get-ItemProperty -Path $uninstallPaths -ErrorAction Stop |
        Where-Object {
            $_.DisplayName -eq $displayName -and
            (
                $_.Publisher -eq $vendorMatch -or
                $_.Publisher -like "*$vendorMatch*"
            )
        }

    $exitCode = 0

    foreach ($app in $apps) {
        $guid = $null

        if ($app.PSChildName -match '^\{[0-9A-Fa-f-]{36}\}$') {
            $guid = $app.PSChildName
        }

        if ($guid) {
            $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $guid /qn REBOOT=ReallySuppress /l*v `"$msiLogFile`"" -Wait -PassThru
            if ($p.ExitCode -ne 0) { $exitCode = $p.ExitCode }
            continue
        }

        if ($app.QuietUninstallString) {
            $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $($app.QuietUninstallString)" -Wait -PassThru
            if ($p.ExitCode -ne 0) { $exitCode = $p.ExitCode }
            continue
        }

        if ($app.UninstallString) {
            $uninstallString = $app.UninstallString

            if ($uninstallString -match '(?i)msiexec(\.exe)?\s+.*\{[0-9A-Fa-f-]{36}\}') {
                $guidFromString = ([regex]::Match($uninstallString, '\{[0-9A-Fa-f-]{36}\}')).Value
                $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $guidFromString /qn REBOOT=ReallySuppress /l*v `"$msiLogFile`"" -Wait -PassThru
                if ($p.ExitCode -ne 0) { $exitCode = $p.ExitCode }
                continue
            }

            $p = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $uninstallString" -Wait -PassThru
            if ($p.ExitCode -ne 0) { $exitCode = $p.ExitCode }
            continue
        }

        # Als er een entry zonder uninstall info is, laat dit falen zodat je het ziet in logging/Intune
        $exitCode = 1
    }

    exit $exitCode
}
finally {
    try { Stop-Transcript | Out-Null } catch [System.InvalidOperationException] {}
}
