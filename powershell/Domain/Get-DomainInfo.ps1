#Requires -Version 5.1
<#
.SYNOPSIS
Verzamelt openbare DNS- en registratiegegevens van een domein.
.DESCRIPTION
Alleen-lezen inventarisatie via Google Public DNS (HTTPS) en de RDAP-dienst
uit het IANA-register. Geen modules, API-sleutels of administratorrechten nodig.
Maakt per uitvoering een unieke map met HTML, JSON en CSV. Google ontvangt
de DNS-vragen; IANA en de registry ontvangen de registratievragen.
Een volledige DNS-zone, onbekende DKIM-selectors en het beheeraccount zijn
niet publiek opvraagbaar. Geef bij voorkeur het geregistreerde hoofddomein op.
.PARAMETER DomainName
Domeinnaam zonder protocol, pad of e-mailadres, bijvoorbeeld bedrijf.nl.
.PARAMETER OutputDirectory
Basismap voor rapporten. Standaard DomainReports in de huidige werkmap.
.PARAMETER DkimSelector
Te controleren DKIM-selectors; vervangt de standaardlijst.
.PARAMETER AdditionalHostnames
Extra relatieve namen binnen het domein, bijvoorbeeld vpn of portal.eu.
.PARAMETER TimeoutSec
Timeout per HTTPS-verzoek. De totale looptijd hangt af van het aantal vragen.
.EXAMPLE
& 'C:\Repo\powershell\Persoonlijk\Get-DomainInfo.ps1' -DomainName 'bedrijf.nl' -OutputDirectory 'C:\Temp\Domeinrapporten'
.EXAMPLE
.\Get-DomainInfo.ps1 -DomainName 'bedrijf.nl' -DkimSelector selector1,selector2,mail2026 -AdditionalHostnames vpn,portal
.LINK
https://developers.google.com/speed/public-dns/docs/doh/json
.LINK
https://www.iana.org/assignments/rdap-dns
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$DomainName,
    [string]$OutputDirectory = (Join-Path (Get-Location).Path 'DomainReports'),
    [string[]]$DkimSelector = @('selector1', 'selector2', 'google', 'default', 's1', 's2', 'k1'),
    [string[]]$AdditionalHostnames = @(),
    [ValidateRange(3, 120)]
    [int]$TimeoutSec = 15
)

$ErrorActionPreference = 'Stop'
$idn = New-Object System.Globalization.IdnMapping
try { $domain = $idn.GetAscii($DomainName.Trim().TrimEnd('.')).ToLowerInvariant() }
catch { throw 'Ongeldige domeinnaam. Gebruik bijvoorbeeld bedrijf.nl.' }
if ($domain.Length -gt 253 -or $domain -notmatch '^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?$') {
    throw 'Geef een geldige domeinnaam op, zonder https://, pad, poort of e-mailadres.'
}
foreach ($label in @($DkimSelector) + @($AdditionalHostnames)) {
    if ([string]::IsNullOrWhiteSpace($label) -or $label -notmatch '^[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*$' -or
        @($label.Split('.') | Where-Object { $_.Length -gt 63 }).Count -gt 0 -or
        "$label._domainkey.$domain".Length -gt 253) {
        throw "Ongeldige relatieve hostnaam of DKIM-selector: $label"
    }
}

$runName = '{0}_{1}_{2}' -f $domain, (Get-Date -Format 'yyyyMMdd_HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$reportDirectory = (New-Item -ItemType Directory -Path (Join-Path $OutputDirectory $runName)).FullName
$queries = New-Object 'System.Collections.Generic.List[object]'
$records = New-Object 'System.Collections.Generic.List[object]'
$cache = @{}
$typeNumbers = @{ A=1; NS=2; CNAME=5; SOA=6; PTR=12; MX=15; TXT=16; AAAA=28; SRV=33; NAPTR=35; DS=43; DNSKEY=48; TLSA=52; SVCB=64; HTTPS=65; CAA=257 }
$typeNames = @{}
foreach ($key in $typeNumbers.Keys) { $typeNames[[int]$typeNumbers[$key]] = $key }
$startedUtc = [DateTime]::UtcNow.ToString('o')

function Invoke-JsonRequest {
    param([string]$Uri)
    Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec $TimeoutSec -MaximumRedirection 3 `
        -Headers @{ Accept = 'application/rdap+json, application/json'; 'User-Agent' = 'DomainInfo/1.0' } -ErrorAction Stop
}

function Get-PublicDns {
    param([string]$Name, [string]$Type)
    $Name = $Name.TrimEnd('.').ToLowerInvariant()
    $key = "$Name|$Type"
    if ($cache.ContainsKey($key)) { return }
    $cache[$key] = $true
    $uri = 'https://dns.google/resolve?name={0}&type={1}&do=true&cd=false&edns_client_subnet=0.0.0.0%2F0' -f [uri]::EscapeDataString($Name), $typeNumbers[$Type]
    $entry = [ordered]@{ Name=$Name; Type=$Type; Status=''; Rcode=$null; AuthenticatedData=$null; CheckedUtc=[DateTime]::UtcNow.ToString('o'); Source=$uri; Error=$null; Raw=$null }
    try {
        $reply = Invoke-JsonRequest $uri
        if ($null -eq $reply.Status) { throw 'DNS-antwoord bevat geen statuscode.' }
        $entry.Raw = $reply
        $entry.Rcode = [int]$reply.Status
        $entry.AuthenticatedData = $reply.AD
        $entry.Status = switch ([int]$reply.Status) {
            0 { if (@($reply.Answer | Where-Object { $_.type -eq $typeNumbers[$Type] }).Count) { 'ANSWER' } else { 'NO_DATA' } }
            2 { 'SERVFAIL' }
            3 { 'NXDOMAIN' }
            5 { 'REFUSED' }
            default { 'DNS_ERROR' }
        }
        # Bewaar ook CNAMEs en DNSSEC-records; een CNAME alleen is geen antwoord op A/TXT.
        foreach ($answer in @($reply.Answer)) {
            if ($null -eq $answer) { continue }
            $recordType = $typeNames[[int]$answer.type]
            if (-not $recordType) { $recordType = 'TYPE{0}' -f $answer.type }
            $records.Add([pscustomobject]@{
                QueryName=$Name; QueryType=$Type; Name=$answer.name; Type=$recordType
                TTL=$answer.TTL; Value=$answer.data; DnsStatus=$entry.Status
            })
        }
    }
    catch { $entry.Status = 'REQUEST_FAILED'; $entry.Error = $_.Exception.Message }
    $queries.Add([pscustomobject]$entry)
}

function Get-RdapEntities {
    param($Entities, [int]$Depth = 0)
    if ($Depth -gt 8) { return }
    foreach ($entity in @($Entities)) {
        if ($null -eq $entity) { continue }
        $name = ''; $email = ''; $phone = ''; $website = ''
        if ($entity.vcardArray -and $entity.vcardArray.Count -ge 2) {
            foreach ($field in $entity.vcardArray[1]) {
                switch ($field[0]) {
                    'fn' { $name = @($field[3]) -join ', ' }
                    'email' { $email = @($field[3]) -join ', ' }
                    'tel' { $phone = @($field[3]) -join ', ' }
                    'url' { $website = @($field[3]) -join ', ' }
                }
            }
        }
        [pscustomobject]@{ Role=(@($entity.roles) -join ', '); Name=$name; Handle=$entity.handle; Email=$email; Phone=$phone; Website=$website }
        if ($entity.entities) { Get-RdapEntities $entity.entities ($Depth + 1) }
    }
}

function Get-DomainRegistration {
    $attempts = New-Object 'System.Collections.Generic.List[object]'
    $result = [ordered]@{ Status='UNAVAILABLE'; Source=$null; Error=$null; Entities=@(); Events=@(); Nameservers=@(); DomainStatus=@(); SecureDNS=$null; Attempts=@(); Raw=$null }
    try {
        $bootstrap = Invoke-JsonRequest 'https://data.iana.org/rdap/dns.json'
        $bestLength = 0; $bases = @()
        foreach ($service in $bootstrap.services) {
            foreach ($suffix in $service[0]) {
                if (($domain -eq $suffix -or $domain.EndsWith(".$suffix")) -and $suffix.Length -gt $bestLength) {
                    $bestLength = $suffix.Length; $bases = @($service[1])
                }
            }
        }
        if (-not $bases.Count) { throw 'Geen RDAP-dienst voor deze extensie in het IANA-register.' }
        foreach ($base in $bases) {
            if ($base -notmatch '^https://') { continue }
            $uri = $base.TrimEnd('/') + '/domain/' + [uri]::EscapeDataString($domain)
            try {
                $data = Invoke-JsonRequest $uri
                if ($data.objectClassName -ne 'domain') { throw 'RDAP-antwoord is geen domeinobject.' }
                $attempts.Add([pscustomobject]@{ Source=$uri; Status='OK'; Error=$null })
                $result.Status = 'OK'; $result.Source = $uri; $result.Raw = $data
                $result.Entities = @(Get-RdapEntities $data.entities)
                $result.Events = @($data.events | Select-Object eventAction, eventDate)
                $result.Nameservers = @($data.nameservers | ForEach-Object { $_.ldhName })
                $result.DomainStatus = @($data.status)
                $result.SecureDNS = $data.secureDNS
                break
            }
            catch { $attempts.Add([pscustomobject]@{ Source=$uri; Status='FAILED'; Error=$_.Exception.Message }) }
        }
        if ($result.Status -ne 'OK') { throw 'De RDAP-dienst gaf geen bruikbaar domeinantwoord. Zie Attempts; gebruik het geregistreerde hoofddomein.' }
    }
    catch { $result.Error = $_.Exception.Message }
    $result.Attempts = @($attempts.ToArray())
    [pscustomobject]$result
}

function ConvertTo-ReportTable {
    param([object[]]$Rows)
    if (-not $Rows.Count) { return '<p>Geen gegevens ontvangen.</p>' }
    ($Rows | ConvertTo-Html -Fragment) -join [Environment]::NewLine
}

# Windows PowerShell 5.1 kan anders nog een verouderd TLS-protocol kiezen.
$previousTls = [Net.ServicePointManager]::SecurityProtocol
try {
    [Net.ServicePointManager]::SecurityProtocol = $previousTls -bor [Net.SecurityProtocolType]::Tls12
    Write-Host "Openbare registratiegegevens ophalen voor $domain..." -ForegroundColor Cyan
    $registration = Get-DomainRegistration
    Write-Host 'DNS, e-mailrecords en veelgebruikte hostnamen controleren...'
    foreach ($type in @('A','AAAA','NS','SOA','MX','TXT','CAA','DS','DNSKEY','HTTPS','SVCB','NAPTR')) { Get-PublicDns $domain $type }
    foreach ($label in @('_dmarc','_mta-sts','_smtp._tls','default._bimi')) { Get-PublicDns "$label.$domain" 'TXT' }
    foreach ($label in @('www','mail','smtp','imap','pop','autodiscover','autoconfig','mta-sts','ftp') + @($AdditionalHostnames) | Select-Object -Unique) {
        foreach ($type in @('A','AAAA','CNAME')) { Get-PublicDns "$label.$domain" $type }
    }
    foreach ($selector in $DkimSelector | Select-Object -Unique) {
        foreach ($type in @('TXT','CNAME')) { Get-PublicDns "$selector._domainkey.$domain" $type }
    }
    foreach ($label in @('_autodiscover._tcp','_sip._tls','_sip._tcp','_sipfederationtls._tcp','_submission._tcp','_imaps._tcp')) {
        Get-PublicDns "$label.$domain" 'SRV'
    }
    # Adressen van gevonden mail- en DNS-servers, met een bovengrens voor grote antwoorden.
    $targets = @($records.ToArray() | Where-Object { $_.Type -in @('NS','MX') -and $_.DnsStatus -eq 'ANSWER' } | ForEach-Object {
        ($_.Value -split '\s+')[-1].TrimEnd('.')
    } | Where-Object { $_ } | Sort-Object -Unique | Select-Object -First 30)
    foreach ($target in $targets) { Get-PublicDns $target 'A'; Get-PublicDns $target 'AAAA' }
    $addresses = @($records.ToArray() | Where-Object { $_.Type -in @('A','AAAA') -and $_.DnsStatus -eq 'ANSWER' } | Select-Object -ExpandProperty Value -Unique | Select-Object -First 40)
    foreach ($address in $addresses) {
        $ip = $null
        if (-not [Net.IPAddress]::TryParse($address, [ref]$ip)) { continue }
        if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
            $bytes = $ip.GetAddressBytes(); [array]::Reverse($bytes)
            $reverseName = ($bytes -join '.') + '.in-addr.arpa'
        }
        else {
            $hex = ([BitConverter]::ToString($ip.GetAddressBytes()) -replace '-', '').ToLowerInvariant().ToCharArray()
            [array]::Reverse($hex); $reverseName = ($hex -join '.') + '.ip6.arpa'
        }
        Get-PublicDns $reverseName 'PTR'
    }
}
finally { [Net.ServicePointManager]::SecurityProtocol = $previousTls }

$uniqueRecords = @($records.ToArray() | Sort-Object Name, Type, Value, TTL -Unique)
$dnsServers = @($uniqueRecords | Where-Object { $_.Type -eq 'NS' -and $_.Name.TrimEnd('.') -eq $domain } | Select-Object -ExpandProperty Value)
$mailServers = @($uniqueRecords | Where-Object { $_.Type -eq 'MX' -and $_.Name.TrimEnd('.') -eq $domain } | Select-Object -ExpandProperty Value)
$registrars = @($registration.Entities | Where-Object { ($_.Role -split ', ') -contains 'registrar' } | ForEach-Object { if ($_.Name) { $_.Name } else { $_.Handle } })
$failedQueries = @($queries.ToArray() | Where-Object { $_.Status -notin @('ANSWER','NO_DATA','NXDOMAIN') })
$limitations = @(
    'Dit is een openbare momentopname via Google Public DNS. Caches, split-DNS en interne records kunnen een ander beeld geven.',
    'DNS is niet volledig te enumereren: dit rapport bevat alleen de expliciet bevraagde namen en types. Geen zone-export.',
    'Registrar (registratie), DNS-hosting (nameservers), mailhosting en websitehosting kunnen verschillende partijen zijn.',
    'Nameservers en MX-doelen zijn technische aanwijzingen; een reseller, contractpartij, beheerportaal of beheeraccount is daarmee niet bewezen.',
    'IP-adressen kunnen bij een CDN of proxy horen en onthullen dan niet de oorspronkelijke webhost.',
    'DKIM wordt alleen voor de opgegeven selectors gecontroleerd. Geen antwoord betekent niet dat DKIM ontbreekt.',
    'SPF, DMARC, DKIM, MTA-STS en BIMI worden verzameld, niet inhoudelijk of via verzonden e-mail gevalideerd. SPF includes worden niet recursief onderzocht.',
    'AD=true betekent dat de resolver dat DNS-antwoord heeft gevalideerd. AD=false is op zichzelf geen bewijs dat DNSSEC ontbreekt of defect is.',
    'NO_DATA: geen record van het gevraagde type; NXDOMAIN: bevraagde naam bestaat niet volgens de resolver; REQUEST_FAILED/SERVFAIL/REFUSED: controle niet geslaagd.',
    'Ontbrekende RDAP-gegevens kunnen worden veroorzaakt door privacy, ontbrekende ondersteuning, een subdomein of een mislukte aanvraag; ze bewijzen niet dat een domein vrij is.',
    'Maximaal 30 gevonden NS/MX-hostnamen en 40 gevonden IP-adressen worden aanvullend onderzocht. Geen poortscan of zone-transfer.'
)
$summary = @(
    [pscustomobject]@{ Onderdeel='Domein'; Waarde=$domain },
    [pscustomobject]@{ Onderdeel='Starttijd (UTC)'; Waarde=$startedUtc },
    [pscustomobject]@{ Onderdeel='Registratiebron'; Waarde=$registration.Source },
    [pscustomobject]@{ Onderdeel='RDAP-status'; Waarde=$registration.Status },
    [pscustomobject]@{ Onderdeel='Registrar'; Waarde=$(if ($registrars.Count) { $registrars -join '; ' } else { 'Niet vastgesteld uit openbare RDAP-gegevens' }) },
    [pscustomobject]@{ Onderdeel='DNS-nameservers'; Waarde=($dnsServers -join '; ') },
    [pscustomobject]@{ Onderdeel='Mailservers (prioriteit + doel)'; Waarde=($mailServers -join '; ') },
    [pscustomobject]@{ Onderdeel='Beheeraccount / contractpartij'; Waarde='Niet publiek vast te stellen; controleer contracten of vraag de beheerder.' },
    [pscustomobject]@{ Onderdeel='DNS-vragen / mislukte controles'; Waarde=('{0} / {1}' -f $queries.Count, $failedQueries.Count) }
)
$querySummary = @($queries.ToArray() | Select-Object Name,Type,Status,Rcode,AuthenticatedData,CheckedUtc,Error,Source)
$report = [ordered]@{
    SchemaVersion='1.0'; Domain=$domain; StartedUtc=$startedUtc; CompletedUtc=[DateTime]::UtcNow.ToString('o')
    Resolver='Google Public DNS (HTTPS)'; DkimSelectors=$DkimSelector; AdditionalHostnames=$AdditionalHostnames
    Summary=$summary; Limitations=$limitations; Registration=$registration
    Records=$uniqueRecords; Queries=$queries.ToArray()
}
$jsonPath = Join-Path $reportDirectory 'DomainInfo.json'
$report | ConvertTo-Json -Depth 70 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$csvPath = Join-Path $reportDirectory 'DNS-records.csv'
if ($uniqueRecords.Count) {
    $uniqueRecords | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'
} else {
    '"QueryName";"QueryType";"Name";"Type";"TTL";"Value";"DnsStatus"' | Set-Content -LiteralPath $csvPath -Encoding UTF8
}
$querySummary | Export-Csv -LiteralPath (Join-Path $reportDirectory 'DNS-controles.csv') -NoTypeInformation -Encoding UTF8 -Delimiter ';'
$notesHtml = ($limitations | ForEach-Object { '<li>' + [Net.WebUtility]::HtmlEncode($_) + '</li>' }) -join "`n"
$errorHtml = [Net.WebUtility]::HtmlEncode([string]$registration.Error)
$html = @"
<!doctype html><html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Domeinrapport $domain</title><style>
body{font:15px/1.55 Segoe UI,Arial,sans-serif;background:#f3f6fa;color:#16253b;margin:0;padding:32px}
main{max-width:1280px;margin:auto;background:white;padding:30px;border-radius:12px}h1,h2{color:#174879}
table{border-collapse:collapse;width:100%;margin:16px 0 30px;font-size:13px;table-layout:fixed}
th,td{text-align:left;vertical-align:top;padding:9px;border:1px solid #dbe3ee;overflow-wrap:anywhere}th{background:#e9f0f8}
tr:nth-child(even){background:#f7f9fc}li{margin:7px 0}.note{background:#fff5db;padding:16px;border-radius:8px}
@media print{body,main{padding:0;background:white}table{font-size:10px}tr{break-inside:avoid}}
</style></head><body><main><h1>Domeinrapport: $domain</h1>
<p>Openbare inventarisatie. Tijdstippen in UTC; TTL in seconden.</p>
$(ConvertTo-ReportTable $summary)
<h2>Wat betekent dit rapport?</h2><div class="note"><ul>$notesHtml</ul></div>
<h2>Registratie en openbare contactgegevens</h2><p>$errorHtml</p>
$(ConvertTo-ReportTable @($registration.Entities))
<h2>Registratiedatums</h2>$(ConvertTo-ReportTable @($registration.Events))
<h2>Registratiestatus</h2>$(ConvertTo-ReportTable @($registration.DomainStatus | ForEach-Object { [pscustomobject]@{ Status=$_ } }))
<h2>DNS-records</h2>$(ConvertTo-ReportTable @($uniqueRecords | Select-Object Name,Type,TTL,Value,DnsStatus))
<h2>Status per DNS-controle</h2>$(ConvertTo-ReportTable @($querySummary | Select-Object Name,Type,Status,AuthenticatedData,Error))
<h2>RDAP-aanvragen</h2>$(ConvertTo-ReportTable @($registration.Attempts))
<p>Bronnen: <a href="https://developers.google.com/speed/public-dns/docs/doh/json">Google DNS API</a>,
<a href="https://www.iana.org/assignments/rdap-dns">IANA RDAP-register</a>.
Bij ontbrekende registratiegegevens: <a href="https://lookup.icann.org/">ICANN Lookup</a> of voor .nl
<a href="https://www.sidn.nl/whois">SIDN Whois</a>. Ruwe antwoorden en DNSSEC-details staan in DomainInfo.json.</p>
</main></body></html>
"@
$htmlPath = Join-Path $reportDirectory 'DomainInfo.html'
$html | Set-Content -LiteralPath $htmlPath -Encoding UTF8
Write-Host "Rapport opgeslagen: $htmlPath" -ForegroundColor Green
if ($registration.Status -ne 'OK' -or $failedQueries.Count) {
    Write-Warning 'Een of meer controles zijn niet geslaagd. Bekijk de statussen in het rapport; ontbrekende gegevens zijn geen bewijs van afwezigheid.'
}
[pscustomobject]@{ Domain=$domain; ReportDirectory=$reportDirectory; Html=$htmlPath; Json=$jsonPath; DnsCsv=$csvPath; FailedDnsQueries=$failedQueries.Count; RdapStatus=$registration.Status }
