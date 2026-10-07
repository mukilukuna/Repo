# Domeininformatie verzamelen

`Get-DomainInfo.ps1` verzamelt openbare informatie over een domein. Werkt met
Windows PowerShell 5.1 en PowerShell 7, zonder extra modules of administratorrechten.

## Starten

```powershell
& 'C:\Repo\powershell\Domain\Get-DomainInfo.ps1' `
    -DomainName 'bedrijf.nl' `
    -OutputDirectory 'C:\Temp\Domeinrapporten'
```

Vervang `bedrijf.nl` door het geregistreerde hoofddomein. Geef geen URL of
e-mailadres op. Internationale domeinnamen worden omgezet naar punycode.
Zonder `-DomainName` vraagt PowerShell om de naam. Zonder `-OutputDirectory`
vraagt het script om de exportmap. Druk op Enter om `DomainReports` in de
huidige werkmap te gebruiken. Voor automatisch gebruik geef je `-OutputDirectory` mee.

Met `-OutputDirectory` kies je zelf de basismap voor de export. Een ontbrekende
map wordt automatisch aangemaakt, inclusief bovenliggende mappen. Een relatief
pad, zoals `.\Exports`, wordt bepaald vanuit de huidige werkmap. Iedere uitvoering
maakt binnen de gekozen map een unieke submap voor de HTML-, JSON- en CSV-bestanden.
Een pad dat naar een bestaand bestand verwijst geeft een foutmelding.
Het script gebruikt hiervoor `..\Common\ExportPath.ps1` en de functie
`Resolve-ExportDirectory`, net als de andere exportscripts. Bewaar de mapstructuur
`powershell/Domain` en `powershell/Common` als je het script kopieert.

Extra hostnamen of eigen DKIM-selectors:

```powershell
& 'C:\Repo\powershell\Domain\Get-DomainInfo.ps1' `
    -DomainName 'bedrijf.nl' `
    -DkimSelector selector1,selector2,google,mail2026 `
    -AdditionalHostnames vpn,portal,remote `
    -OutputDirectory 'C:\Temp\Domeinrapporten'
```

`-DkimSelector` vervangt de standaardlijst: selector1, selector2, google,
default, s1, s2 en k1. Extra hostnamen zijn relatief aan het opgegeven domein.
Met `-TimeoutSec 8` stel je de timeout per verzoek in; de standaard is 15 seconden.
De totale looptijd kan bij netwerkproblemen enkele minuten bedragen.

## Wat krijg je?

Iedere uitvoering maakt een unieke submap met vier bestanden:

| Bestand | Inhoud |
| --- | --- |
| DomainInfo.html | Leesbaar rapport; open in een browser, eventueel afdrukken als PDF |
| DomainInfo.json | Volledige resultaten met bron-URL's, ruwe antwoorden en tijdstippen |
| DNS-records.csv | Gevonden records, puntkomma als scheidingsteken |
| DNS-controles.csv | Iedere uitgevoerde DNS-vraag, inclusief fouten en ontbrekende antwoorden |

Het rapport bevat:

- Registrar, openbare RDAP-contacten (ook reseller/abuse indien gepubliceerd),
  registratiedatums, wijzigingsdatums, eventuele vervaldatum en domeinstatussen.
- Nameservers en SOA; A, AAAA, MX, TXT, CAA, DS, DNSKEY, HTTPS, SVCB en NAPTR.
- SPF in TXT, DMARC, DKIM voor de opgegeven selectors, MTA-STS, TLS-RPT en BIMI.
- A/AAAA/CNAME voor www, mail, smtp, imap, pop, autodiscover, autoconfig, mta-sts,
  ftp en opgegeven extra hostnamen.
- SRV voor autodiscover, SIP, SIP federation, submission en IMAPS.
- A/AAAA van maximaal 30 gevonden NS/MX-hostnamen; PTR van maximaal 40 gevonden IP-adressen.

## Waar wordt het domein beheerd?

De **registrar** verzorgt de registratie. De **nameservers** wijzen op de
DNS-infrastructuur. De **MX-records** wijzen op de inkomende mailafhandeling.
Dit kunnen verschillende bedrijven zijn. Een mailgateway kan voor de eigenlijke
mailomgeving staan; een CDN/proxy kan de oorspronkelijke webhost verbergen.

Een reseller, het bedrijf dat de factuur stuurt, een specifiek beheerportaal en
het account waarmee je inlogt zijn niet betrouwbaar uit DNS af te leiden.
Controleer daarvoor contracten of vraag de bestaande beheerder. Sommige
registratiegegevens zijn afgeschermd of ontbreken bij de openbare RDAP-dienst.

## Statussen en beperkingen

| Status | Betekenis |
| --- | --- |
| ANSWER | Antwoord met het gevraagde recordtype ontvangen |
| NO_DATA | DNS-antwoord ontvangen, geen record van het gevraagde type |
| NXDOMAIN | Bevraagde naam bestaat niet volgens deze resolver |
| SERVFAIL / REFUSED / DNS_ERROR | DNS-controle niet geslaagd |
| REQUEST_FAILED | HTTPS-aanvraag of verwerking van antwoord mislukt |

Een succesvolle opvraag is geen bewijs dat een dienst gezond of correct
geconfigureerd is. SPF-includes worden niet recursief nagekeken; mailbeleid en
DKIM worden niet via testmail gevalideerd. DNSSEC `AuthenticatedData=true`
betekent dat de resolver dat antwoord valideerde. `false` bewijst op zichzelf
geen ontbrekende of defecte DNSSEC-configuratie. Ruwe DNSSEC- en registrygegevens
blijven beschikbaar in JSON.

Een openbare DNS-zone is niet volledig opvraagbaar. Onbekende subdomeinen,
onbekende DKIM-selectors en interne DNS-records ontbreken. Voor een volledige
zone-export heb je toegang tot de DNS-provider nodig. Het script doet geen
zone-transfer of poortscan. RDAP bevraagt exact het ingevoerde domein: bij een
subdomein kan registratie ontbreken, ook als het hoofddomein geregistreerd is.

Het script vraagt openbare DNS-informatie op bij Google via HTTPS en zoekt de
RDAP-dienst bij IANA. Daarvoor is internettoegang op poort 443 nodig. De betrokken
diensten ontvangen de opgevraagde namen. Resultaten komen uit een publieke
resolvercache en kunnen afwijken van interne DNS of recent aangepaste records.
Bij RDAP-problemen blijft het DNS-rapport beschikbaar. Gebruik voor handmatige
nacontrole [SIDN Whois](https://www.sidn.nl/whois) of
[ICANN Lookup](https://lookup.icann.org/).

## Bronnen

- [Google Public DNS JSON API](https://developers.google.com/speed/public-dns/docs/doh/json)
- [IANA RDAP-bootstrapregister](https://www.iana.org/assignments/rdap-dns)
- [SIDN: uitleg Whois en onderscheid registrar/reseller](https://www.sidn.nl/nl-domeinnaam/uitleg-whois)
