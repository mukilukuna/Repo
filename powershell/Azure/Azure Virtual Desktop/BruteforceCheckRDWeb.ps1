<# 
=====================================================================
RDWeb / RD Gateway brute-force inventarisatie collector
Read-only: leest alleen logs uit en maakt een zipbestand.
=====================================================================
#>

# Periode aanpassen
$StartTimeLocal = (Get-Date).AddDays(-7)
$EndTimeLocal   = Get-Date

# Outputlocatie
$OutputBase = "C:\Temp\RDWeb-Bruteforce-Collect"

# URI-filters voor RDWeb/RD Gateway/IIS
$UriPatterns = @(
    "/RDWeb*",
    "/rpc*",
    "/RemoteDesktopGateway*"
)

# ------------------------------------------------------------
# Voorbereiding
# ------------------------------------------------------------

$RunStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$OutputFolder = Join-Path $OutputBase "RDWeb-Bruteforce-$RunStamp"
$EventFolder = Join-Path $OutputFolder "EventLogs"
$IisFolder = Join-Path $OutputFolder "IISLogs"
$HttpErrFolder = Join-Path $OutputFolder "HTTPERR"
$SystemFolder = Join-Path $OutputFolder "SystemInfo"

New-Item -Path $EventFolder, $IisFolder, $HttpErrFolder, $SystemFolder -ItemType Directory -Force | Out-Null

$Notes = New-Object System.Collections.Generic.List[string]

function Add-Note {
    param([string]$Text)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Text
    $Notes.Add($line)
    Write-Host $line
}

Add-Note "Start collectie."
Add-Note "Periode lokaal: $StartTimeLocal t/m $EndTimeLocal"
Add-Note "Computer: $env:COMPUTERNAME"
Add-Note "User: $env:USERDOMAIN\$env:USERNAME"

# ------------------------------------------------------------
# Systeeminfo verzamelen
# ------------------------------------------------------------

try {
    hostname | Out-File (Join-Path $SystemFolder "hostname.txt")
    whoami /all | Out-File (Join-Path $SystemFolder "whoami_all.txt")
    ipconfig /all | Out-File (Join-Path $SystemFolder "ipconfig_all.txt")
    route print | Out-File (Join-Path $SystemFolder "route_print.txt")
    netstat -ano | Out-File (Join-Path $SystemFolder "netstat_ano.txt")
    tasklist /svc | Out-File (Join-Path $SystemFolder "tasklist_svc.txt")
    systeminfo | Out-File (Join-Path $SystemFolder "systeminfo.txt")
    Get-TimeZone | Out-File (Join-Path $SystemFolder "timezone.txt")
    Get-Date | Out-File (Join-Path $SystemFolder "collection_time.txt")
    Add-Note "Systeeminfo verzameld."
}
catch {
    Add-Note "Fout bij verzamelen systeeminfo: $($_.Exception.Message)"
}

# ------------------------------------------------------------
# Event logs uitlezen
# ------------------------------------------------------------

function Convert-EventToFlatObject {
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Eventing.Reader.EventRecord]$Event
    )

    try {
        $xml = [xml]$Event.ToXml()

        $obj = [ordered]@{
            TimeCreated      = $Event.TimeCreated
            Id               = $Event.Id
            ProviderName     = $Event.ProviderName
            LogName          = $Event.LogName
            MachineName      = $Event.MachineName
            RecordId         = $Event.RecordId
            LevelDisplayName = $Event.LevelDisplayName
        }

        $index = 0
        foreach ($data in $xml.Event.EventData.Data) {
            $name = $data.Name

            if ([string]::IsNullOrWhiteSpace($name)) {
                $name = "Data$index"
            }

            if ($obj.Contains($name)) {
                $name = "$name`_$index"
            }

            $obj[$name] = [string]$data.'#text'
            $index++
        }

        $obj["Message"] = ($Event.Message -replace "(`r`n|`n|`r)", " | ")

        [pscustomobject]$obj
    }
    catch {
        [pscustomobject]@{
            TimeCreated  = $Event.TimeCreated
            Id           = $Event.Id
            ProviderName = $Event.ProviderName
            LogName      = $Event.LogName
            MachineName  = $Event.MachineName
            RecordId     = $Event.RecordId
            Message      = "Kon event niet volledig parsen: $($_.Exception.Message)"
        }
    }
}

function Export-EventLogRange {
    param(
        [Parameter(Mandatory)]
        [string]$LogName,

        [int[]]$Ids,

        [Parameter(Mandatory)]
        [string]$FilePrefix
    )

    try {
        $logInfo = Get-WinEvent -ListLog $LogName -ErrorAction SilentlyContinue

        if (-not $logInfo) {
            Add-Note "Eventlog niet gevonden: $LogName"
            return
        }

        $filter = @{
            LogName   = $LogName
            StartTime = $StartTimeLocal
            EndTime   = $EndTimeLocal
        }

        if ($Ids -and $Ids.Count -gt 0) {
            $filter["Id"] = $Ids
        }

        $events = Get-WinEvent -FilterHashtable $filter -ErrorAction SilentlyContinue

        if (-not $events) {
            Add-Note "Geen events gevonden in: $LogName"
            return
        }

        $csvPath = Join-Path $EventFolder "$FilePrefix.csv"
        $txtPath = Join-Path $EventFolder "$FilePrefix.messages.txt"
        $countPath = Join-Path $EventFolder "$FilePrefix.counts.csv"

        $flatEvents = $events |
            Sort-Object TimeCreated |
            ForEach-Object { Convert-EventToFlatObject -Event $_ }

        $flatEvents | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

        $flatEvents |
            Select-Object TimeCreated, Id, ProviderName, MachineName, Message |
            Format-List |
            Out-File -FilePath $txtPath -Encoding UTF8

        $flatEvents |
            Group-Object Id |
            Sort-Object Count -Descending |
            Select-Object Count, Name |
            Export-Csv -Path $countPath -NoTypeInformation -Encoding UTF8

        Add-Note "Events geëxporteerd: $LogName naar $csvPath"
    }
    catch {
        Add-Note "Fout bij uitlezen eventlog '$LogName': $($_.Exception.Message)"
    }
}

# Security events:
# 4625 = failed logon
# 4740 = account locked out
# 4771 = Kerberos pre-authentication failed
# 4776 = NTLM authentication failed
# 4648 = logon attempted using explicit credentials
Export-EventLogRange -LogName "Security" -Ids @(4625,4740,4771,4776,4648) -FilePrefix "Security_AuthFailures_Lockouts"

# RDS/RD Gateway logs
Export-EventLogRange -LogName "Microsoft-Windows-TerminalServices-Gateway/Operational" -FilePrefix "RDS_Gateway_Operational"
Export-EventLogRange -LogName "Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational" -FilePrefix "RDS_RemoteConnectionManager_Operational"
Export-EventLogRange -LogName "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational" -FilePrefix "RDS_LocalSessionManager_Operational"

# IIS eventlog, indien aanwezig
Export-EventLogRange -LogName "Microsoft-Windows-IIS-Logging/Logs" -FilePrefix "IIS_EventLog"

# Application/System beperkt meenemen voor web/RDS fouten
Export-EventLogRange -LogName "Application" -Ids @(1000,1001,1002,1026,1309) -FilePrefix "Application_WebErrors"
Export-EventLogRange -LogName "System" -Ids @(7031,7034,7036,7040,7045) -FilePrefix "System_ServiceEvents"

# ------------------------------------------------------------
# IIS W3C logs vinden en parsen
# ------------------------------------------------------------

function ConvertFrom-W3CLog {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $fields = $null

    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ($line -like "#Fields:*") {
            $fields = $line.Substring(8).Trim() -split " "
            continue
        }

        if ($line.StartsWith("#") -or [string]::IsNullOrWhiteSpace($line) -or -not $fields) {
            continue
        }

        $values = $line -split " "

        if ($values.Count -lt $fields.Count) {
            continue
        }

        $obj = [ordered]@{}

        for ($i = 0; $i -lt $fields.Count; $i++) {
            $obj[$fields[$i]] = $values[$i]
        }

        if ($obj.Contains("date") -and $obj.Contains("time")) {
            try {
                $utc = [datetime]::SpecifyKind(
                    [datetime]::Parse("$($obj['date']) $($obj['time'])"),
                    [System.DateTimeKind]::Utc
                )

                $obj["DateTimeLocal"] = $utc.ToLocalTime()
                $obj["LogFile"] = $Path
            }
            catch {
                $obj["DateTimeLocal"] = $null
                $obj["LogFile"] = $Path
            }
        }

        [pscustomobject]$obj
    }
}

function Test-UriMatch {
    param(
        [string]$Uri
    )

    if ([string]::IsNullOrWhiteSpace($Uri)) {
        return $false
    }

    foreach ($pattern in $UriPatterns) {
        if ($Uri -like $pattern) {
            return $true
        }
    }

    return $false
}

$CandidateIisRoots = @()

Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    $CandidateIisRoots += (Join-Path $_.Root "inetpub\logs\LogFiles")
}

$CandidateIisRoots = $CandidateIisRoots | Sort-Object -Unique

$CandidateIisRoots | Out-File (Join-Path $IisFolder "IIS_LogPaths_Checked.txt") -Encoding UTF8

$ExistingIisRoots = $CandidateIisRoots | Where-Object { Test-Path $_ }

if (-not $ExistingIisRoots) {
    Add-Note "Geen IIS logmap gevonden. Verwachte locatie zoals C:\inetpub\logs\LogFiles bestaat niet."
}
else {
    Add-Note "IIS logmap gevonden: $($ExistingIisRoots -join ', ')"

    $StartUtc = $StartTimeLocal.ToUniversalTime().AddDays(-1)
    $EndUtc   = $EndTimeLocal.ToUniversalTime().AddDays(1)

    $DateTokens = New-Object System.Collections.Generic.List[string]
    $d = $StartUtc.Date

    while ($d -le $EndUtc.Date) {
        $DateTokens.Add($d.ToString("yyMMdd"))
        $d = $d.AddDays(1)
    }

    $IisRawFolder = Join-Path $IisFolder "Raw"
    New-Item -Path $IisRawFolder -ItemType Directory -Force | Out-Null

    $iisFiles = foreach ($root in $ExistingIisRoots) {
        Get-ChildItem -Path $root -Recurse -Filter "u_ex*.log" -ErrorAction SilentlyContinue |
            Where-Object {
                $token = $_.BaseName -replace "^u_ex", ""
                ($DateTokens -contains $token) -or
                ($_.LastWriteTime -ge $StartTimeLocal.AddDays(-1) -and $_.LastWriteTime -le $EndTimeLocal.AddDays(1))
            }
    }

    if (-not $iisFiles) {
        Add-Note "Geen IIS logbestanden gevonden binnen de periode."
    }
    else {
        Add-Note "Aantal IIS logbestanden gevonden: $($iisFiles.Count)"

        foreach ($file in $iisFiles) {
            try {
                $relativeName = ($file.FullName -replace "[:\\]", "_").TrimStart("_")
                Copy-Item -Path $file.FullName -Destination (Join-Path $IisRawFolder $relativeName) -Force
            }
            catch {
                Add-Note "Kon IIS raw log niet kopiëren: $($file.FullName) - $($_.Exception.Message)"
            }
        }

        $parsedIis = foreach ($file in $iisFiles) {
            try {
                ConvertFrom-W3CLog -Path $file.FullName
            }
            catch {
                Add-Note "Kon IIS log niet parsen: $($file.FullName) - $($_.Exception.Message)"
            }
        }

        $filteredIis = $parsedIis |
            Where-Object {
                $_.DateTimeLocal -and
                $_.DateTimeLocal -ge $StartTimeLocal -and
                $_.DateTimeLocal -le $EndTimeLocal -and
                (Test-UriMatch -Uri $_.'cs-uri-stem')
            } |
            Sort-Object DateTimeLocal

        $filteredIisPath = Join-Path $IisFolder "IIS_RDWeb_Filtered.csv"
        $filteredIis | Export-Csv -Path $filteredIisPath -NoTypeInformation -Encoding UTF8

        $filteredIis |
            Group-Object 'c-ip' |
            Sort-Object Count -Descending |
            Select-Object Count, Name |
            Export-Csv -Path (Join-Path $IisFolder "IIS_Top_ClientIPs.csv") -NoTypeInformation -Encoding UTF8

        $filteredIis |
            Group-Object {
                if ($_.DateTimeLocal) {
                    $_.DateTimeLocal.ToString("yyyy-MM-dd HH:00")
                }
            } |
            Sort-Object Name |
            Select-Object Name, Count |
            Export-Csv -Path (Join-Path $IisFolder "IIS_Requests_Per_Hour.csv") -NoTypeInformation -Encoding UTF8

        $filteredIis |
            Group-Object 'sc-status','sc-substatus','sc-win32-status' |
            Sort-Object Count -Descending |
            Select-Object Count, Name |
            Export-Csv -Path (Join-Path $IisFolder "IIS_Status_Counts.csv") -NoTypeInformation -Encoding UTF8

        $filteredIis |
            Select-Object `
                DateTimeLocal,
                @{Name="ClientIP";Expression={$_.'c-ip'}},
                @{Name="Method";Expression={$_.'cs-method'}},
                @{Name="Uri";Expression={$_.'cs-uri-stem'}},
                @{Name="Query";Expression={$_.'cs-uri-query'}},
                @{Name="Username";Expression={$_.'cs-username'}},
                @{Name="Status";Expression={$_.'sc-status'}},
                @{Name="SubStatus";Expression={$_.'sc-substatus'}},
                @{Name="Win32Status";Expression={$_.'sc-win32-status'}},
                @{Name="UserAgent";Expression={$_.'cs(User-Agent)'}},
                LogFile |
            Export-Csv -Path (Join-Path $IisFolder "IIS_RDWeb_ShortView.csv") -NoTypeInformation -Encoding UTF8

        Add-Note "IIS RDWeb logs gefilterd en geëxporteerd."
    }
}

# ------------------------------------------------------------
# HTTPERR logs verzamelen
# ------------------------------------------------------------

$HttpErrPath = Join-Path $env:SystemRoot "System32\LogFiles\HTTPERR"
$HttpErrPath | Out-File (Join-Path $HttpErrFolder "HTTPERR_Path_Checked.txt") -Encoding UTF8

if (Test-Path $HttpErrPath) {
    Add-Note "HTTPERR map gevonden: $HttpErrPath"

    $HttpErrRawFolder = Join-Path $HttpErrFolder "Raw"
    New-Item -Path $HttpErrRawFolder -ItemType Directory -Force | Out-Null

    $StartUtc = $StartTimeLocal.ToUniversalTime().AddDays(-1)
    $EndUtc   = $EndTimeLocal.ToUniversalTime().AddDays(1)

    $DateTokens = New-Object System.Collections.Generic.List[string]
    $d = $StartUtc.Date

    while ($d -le $EndUtc.Date) {
        $DateTokens.Add($d.ToString("yyMMdd"))
        $d = $d.AddDays(1)
    }

    $httpErrFiles = Get-ChildItem -Path $HttpErrPath -Filter "httperr*.log" -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.LastWriteTime -ge $StartTimeLocal.AddDays(-1) -and $_.LastWriteTime -le $EndTimeLocal.AddDays(1))
        }

    if (-not $httpErrFiles) {
        Add-Note "Geen HTTPERR logbestanden gevonden binnen de periode."
    }
    else {
        foreach ($file in $httpErrFiles) {
            try {
                Copy-Item -Path $file.FullName -Destination (Join-Path $HttpErrRawFolder $file.Name) -Force
            }
            catch {
                Add-Note "Kon HTTPERR raw log niet kopiëren: $($file.FullName) - $($_.Exception.Message)"
            }
        }

        $parsedHttpErr = foreach ($file in $httpErrFiles) {
            try {
                ConvertFrom-W3CLog -Path $file.FullName
            }
            catch {
                Add-Note "Kon HTTPERR log niet parsen: $($file.FullName) - $($_.Exception.Message)"
            }
        }

        $filteredHttpErr = $parsedHttpErr |
            Where-Object {
                $_.DateTimeLocal -and
                $_.DateTimeLocal -ge $StartTimeLocal -and
                $_.DateTimeLocal -le $EndTimeLocal
            } |
            Sort-Object DateTimeLocal

        $filteredHttpErr | Export-Csv -Path (Join-Path $HttpErrFolder "HTTPERR_Filtered.csv") -NoTypeInformation -Encoding UTF8

        $filteredHttpErr |
            Group-Object 'c-ip' |
            Sort-Object Count -Descending |
            Select-Object Count, Name |
            Export-Csv -Path (Join-Path $HttpErrFolder "HTTPERR_Top_ClientIPs.csv") -NoTypeInformation -Encoding UTF8

        $filteredHttpErr |
            Group-Object 's-reason' |
            Sort-Object Count -Descending |
            Select-Object Count, Name |
            Export-Csv -Path (Join-Path $HttpErrFolder "HTTPERR_Reasons.csv") -NoTypeInformation -Encoding UTF8

        Add-Note "HTTPERR logs verzameld."
    }
}
else {
    Add-Note "HTTPERR map niet gevonden: $HttpErrPath"
}

# ------------------------------------------------------------
# Samenvatting maken
# ------------------------------------------------------------

$Notes | Out-File -Path (Join-Path $OutputFolder "Collector_Notes.txt") -Encoding UTF8

try {
    Get-ChildItem -Path $OutputFolder -Recurse |
        Select-Object FullName, Length, LastWriteTime |
        Export-Csv -Path (Join-Path $OutputFolder "Collected_Files_Index.csv") -NoTypeInformation -Encoding UTF8
}
catch {
    Add-Note "Kon file index niet maken: $($_.Exception.Message)"
}

# ------------------------------------------------------------
# Zip maken
# ------------------------------------------------------------

$ZipPath = "$OutputFolder.zip"

try {
    if (Test-Path $ZipPath) {
        Remove-Item $ZipPath -Force
    }

    Compress-Archive -Path $OutputFolder -DestinationPath $ZipPath -Force
    Add-Note "Zipbestand gemaakt: $ZipPath"

    $Notes | Out-File -Path (Join-Path $OutputFolder "Collector_Notes.txt") -Encoding UTF8

    Write-Host ""
    Write-Host "Klaar."
    Write-Host "Zipbestand:"
    Write-Host $ZipPath
}
catch {
    Add-Note "Fout bij maken zipbestand: $($_.Exception.Message)"
    Write-Host "Outputmap staat hier:"
    Write-Host $OutputFolder
}