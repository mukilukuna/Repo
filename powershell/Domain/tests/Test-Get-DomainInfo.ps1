#Requires -Version 5.1
# Integration checks with real report/ZIP files and simulated HTTPS responses.
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path $PSScriptRoot '../Get-DomainInfo.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('GetDomainInfoTests_' + [guid]::NewGuid().ToString('N'))
$domainInfoTestState = [pscustomobject]@{
    Requests = New-Object 'System.Collections.Generic.List[string]'
    Prompts = New-Object 'System.Collections.Generic.List[string]'
    Replies = New-Object 'System.Collections.Generic.Queue[string]'
    DnsStatus = 'ANSWER'
    Count = 0
    CaseRoot = ''
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Read-Host {
    param([string]$Prompt)
    $domainInfoTestState.Prompts.Add($Prompt)
    if (-not $domainInfoTestState.Replies.Count) { throw "Unexpected prompt: $Prompt" }
    $domainInfoTestState.Replies.Dequeue()
}

function Invoke-RestMethod {
    [CmdletBinding()]
    param([string]$Uri, $Method, $TimeoutSec, $MaximumRedirection, $Headers)
    $domainInfoTestState.Requests.Add($Uri)
    if ($Uri -eq 'https://data.iana.org/rdap/dns.json') {
        return [pscustomobject]@{ services = @( ,@(@('com'), @('https://rdap.example.test/'))) }
    }
    if ($Uri.StartsWith('https://rdap.example.test/domain/')) {
        return [pscustomobject]@{
            objectClassName='domain'; entities=@(); events=@(); nameservers=@(); status=@('active')
        }
    }
    if (-not $Uri.StartsWith('https://dns.google/resolve?')) { throw "Unexpected URL: $Uri" }
    $answers = @()
    if ($Uri -match '&type=2&') {
        switch ($domainInfoTestState.DnsStatus) {
            'REQUEST_FAILED' { throw 'Simulated HTTPS timeout' }
            'NXDOMAIN' { return [pscustomobject]@{ Status=3; AD=$false; Answer=@() } }
            'SERVFAIL' { return [pscustomobject]@{ Status=2; AD=$false; Answer=@() } }
            'ANSWER' {
                $answers = @(
                    [pscustomobject]@{ name='example.com.'; type=2; TTL=3600; data='ns1.example.net.' },
                    [pscustomobject]@{ name='example.com.'; type=2; TTL=3600; data='ns2.example.net.' }
                )
            }
        }
    }
    elseif ($Uri -match '&type=15&') {
        $answers = @([pscustomobject]@{ name='example.com.'; type=15; TTL=300; data='10 mail.example.net.' })
    }
    [pscustomobject]@{ Status=0; AD=$true; Answer=$answers }
}

function Assert-ZipReport {
    param($Result, [string]$ExpectedDirectory, [bool]$NameserversOnly)
    Assert-True (Test-Path -LiteralPath $Result.Zip -PathType Leaf) 'ZIP is missing'
    Assert-True ((Split-Path $Result.Zip -Parent) -eq $ExpectedDirectory) 'ZIP is outside the selected directory'
    Assert-True (@(Get-ChildItem -LiteralPath $ExpectedDirectory -Directory).Count -eq 0) 'Unpacked reports remain in the export directory'
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Result.Zip)
    try {
        $names = @($archive.Entries | ForEach-Object { $_.FullName } | Sort-Object)
        Assert-True (($names -join '|') -eq 'DNS-controles.csv|DNS-records.csv|DomainInfo.html|DomainInfo.json') 'ZIP does not contain the four report files'
        $reader = New-Object System.IO.StreamReader ($archive.GetEntry('DomainInfo.json').Open())
        try { $report = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }
        Assert-True ($report.Domain -eq 'example.com') 'JSON has the wrong domain'
        Assert-True ($report.NameserversOnly -eq $NameserversOnly) 'JSON has the wrong query scope'
        Assert-True (@($report.Records | Where-Object { $_.Type -eq 'NS' }).Count -eq 2) 'JSON is missing NS results'
        if ($NameserversOnly) {
            Assert-True ($report.Queries.Count -eq 1 -and $null -eq $report.Registration) 'NS-only report included additional lookups'
        }
        else {
            Assert-True ($report.Registration.Status -eq 'OK' -and $report.Queries.Count -gt 1) 'Full report did not collect registration and DNS'
        }
        $reader = New-Object System.IO.StreamReader ($archive.GetEntry('DNS-records.csv').Open())
        try { $csv = @($reader.ReadToEnd() | ConvertFrom-Csv -Delimiter ';') }
        finally { $reader.Dispose() }
        Assert-True (@($csv | Where-Object { $_.Value -eq 'ns1.example.net.' }).Count -eq 1) 'CSV is missing the nameserver'
        Assert-True ($archive.GetEntry('DomainInfo.html').Length -gt 0) 'HTML report is empty'
    }
    finally { $archive.Dispose() }
}

function Invoke-TestCase {
    param([string]$Name, [scriptblock]$Test)
    $domainInfoTestState.Requests.Clear()
    $domainInfoTestState.Prompts.Clear()
    $domainInfoTestState.Replies.Clear()
    $domainInfoTestState.DnsStatus = 'ANSWER'
    $domainInfoTestState.Count++
    $domainInfoTestState.CaseRoot = Join-Path $testRoot ([string]$domainInfoTestState.Count)
    [void][System.IO.Directory]::CreateDirectory($domainInfoTestState.CaseRoot)
    $temporaryBefore = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Directory -Filter 'DomainInfo_*' | Sort-Object FullName | ForEach-Object { $_.FullName }) -join '|'
    Push-Location $domainInfoTestState.CaseRoot
    try {
        & $Test
        $temporaryAfter = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -Directory -Filter 'DomainInfo_*' | Sort-Object FullName | ForEach-Object { $_.FullName }) -join '|'
        Assert-True ($temporaryBefore -eq $temporaryAfter) 'Temporary report directory was not cleaned up'
        Write-Host "PASS: $Name"
    }
    finally { Pop-Location }
}

try {
    Invoke-TestCase 'NS-only defaults to terminal and makes one request without writing files' {
        $tlsBefore = [Net.ServicePointManager]::SecurityProtocol
        $text = & $scriptPath -DomainName example.com -NameserversOnly | Out-String
        Assert-True ($text.Contains('ns1.example.net') -and $text.Contains('ns2.example.net')) 'Terminal did not display both nameservers'
        Assert-True ($domainInfoTestState.Requests.Count -eq 1 -and $domainInfoTestState.Requests[0] -match '&type=2&') 'Quick mode made extra requests'
        Assert-True ($domainInfoTestState.Prompts.Count -eq 0) 'Quick mode prompted unexpectedly'
        Assert-True (@(Get-ChildItem -Force).Count -eq 0) 'Terminal output wrote files'
        Assert-True ([Net.ServicePointManager]::SecurityProtocol -eq $tlsBefore) 'TLS setting was not restored'
    }
    Invoke-TestCase 'Full terminal mode shows DNS and registration without exporting' {
        $text = & $scriptPath -DomainName example.com -OutputMode Terminal | Out-String
        Assert-True ($text.Contains('ns1.example.net') -and $text.Contains('mail.example.net') -and $text.Contains('RDAP-status')) 'Terminal summary or records are missing'
        Assert-True ($domainInfoTestState.Requests.Contains('https://data.iana.org/rdap/dns.json')) 'Registration was not queried'
        Assert-True (@(Get-ChildItem -Force).Count -eq 0 -and $domainInfoTestState.Prompts.Count -eq 0) 'Terminal mode exported or prompted'
    }
    Invoke-TestCase 'Invalid menu choice is retried and Enter chooses terminal' {
        $domainInfoTestState.Replies.Enqueue('invalid')
        $domainInfoTestState.Replies.Enqueue('')
        $text = & $scriptPath -DomainName example.com -WarningAction SilentlyContinue | Out-String
        Assert-True ($domainInfoTestState.Prompts.Count -eq 2 -and $text.Contains('ns1.example.net')) 'Output menu did not retry or choose terminal'
        Assert-True (@(Get-ChildItem -Force).Count -eq 0) 'Default terminal mode wrote files'
    }
    Invoke-TestCase 'ZIP menu uses Common to select a nested export directory' {
        $exportPath = Join-Path $domainInfoTestState.CaseRoot 'parent/Exports [customer]'
        $domainInfoTestState.Replies.Enqueue('z')
        $domainInfoTestState.Replies.Enqueue($exportPath)
        $result = & $scriptPath -DomainName example.com
        Assert-ZipReport $result $exportPath $false
        Assert-True ($domainInfoTestState.Prompts.Count -eq 2) 'Expected an output choice and Common export-path prompt'
    }
    Invoke-TestCase 'Explicit ZIP and legacy OutputDirectory create separate NS-only archives' {
        $first = & $scriptPath -DomainName example.com -NameserversOnly -OutputMode Zip -OutputDirectory './Exports'
        $second = & $scriptPath -DomainName example.com -NameserversOnly -OutputDirectory './Exports'
        Assert-ZipReport $first (Join-Path $domainInfoTestState.CaseRoot 'Exports') $true
        Assert-ZipReport $second (Join-Path $domainInfoTestState.CaseRoot 'Exports') $true
        Assert-True ($first.Zip -ne $second.Zip -and $domainInfoTestState.Requests.Count -eq 2) 'ZIP overwrote an earlier report or quick mode made extra requests'
        Assert-True ($domainInfoTestState.Prompts.Count -eq 0) 'Explicit output directory prompted unexpectedly'
    }
    Invoke-TestCase 'NS failure statuses are visible and distinct from successful answers' {
        foreach ($status in @('NO_DATA', 'NXDOMAIN', 'SERVFAIL', 'REQUEST_FAILED')) {
            $domainInfoTestState.DnsStatus = $status
            $warnings = @()
            $text = & $scriptPath -DomainName example.com -NameserversOnly -WarningVariable warnings -WarningAction SilentlyContinue | Out-String
            Assert-True (($warnings -join ' ').Contains("NS-status: $status")) "Missing NS failure status: $status"
            Assert-True (-not $text.Contains('ns1.example.net')) 'Failure displayed nameservers as if found'
        }
        Assert-True (@(Get-ChildItem -Force).Count -eq 0) 'Failed terminal lookup wrote files'
    }
    Invoke-TestCase 'Output path pointing at a file fails before requests and preserves the file' {
        Set-Content -LiteralPath './keep.txt' -Value 'keep this'
        $failed = $false
        try { & $scriptPath -DomainName example.com -OutputMode Zip -OutputDirectory './keep.txt' | Out-Null }
        catch { $failed = $true }
        Assert-True ($failed -and $domainInfoTestState.Requests.Count -eq 0) 'Invalid export path did not fail before network requests'
        Assert-True ((Get-Content -LiteralPath './keep.txt' -Raw).Trim() -eq 'keep this') 'Existing file was changed'
    }
    Invoke-TestCase 'Report-write failure cleans up staging files without creating a ZIP' {
        function Set-Content {
            [CmdletBinding()]
            param($LiteralPath, $Encoding, [Parameter(ValueFromPipeline)]$Value)
            process { throw 'Simulated report-write failure' }
        }
        $failed = $false
        try { & $scriptPath -DomainName example.com -NameserversOnly -OutputMode Zip -OutputDirectory './Exports' | Out-Null }
        catch { $failed = $_.Exception.Message -like '*Simulated report-write failure*' }
        Assert-True $failed 'Expected report-write failure was not observed'
        Assert-True (@(Get-ChildItem -LiteralPath './Exports' -Force).Count -eq 0) 'Failed export left a partial archive'
    }
    Write-Host "All $($domainInfoTestState.Count) tests passed. No live network requests were made."
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
