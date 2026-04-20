# Installeer de PnP PowerShell-module indien nodig
if (-not (Get-Module -Name PnP.PowerShell -ListAvailable)) {
    Install-Module -Name PnP.PowerShell -Force -AllowClobber
}

# SharePoint-site URL
$SiteUrl = "https://org1.sharepoint.com/sites/OrganizationalAssets/"  # De site waar je bibliotheken wilt aanmaken

# Inloggen met device code
Connect-PnPOnline -Url $SiteUrl -UseWebLogin

# Lijst met documentbibliotheken
$DocLibraries = @(
    "Grootrotterdam",
    "Org2",
    "Peuter&Co",
    "JOZ",
    "SMWR")

# Loop door elke bibliotheek en maak deze aan
foreach ($Library in $DocLibraries) {
    try {
        New-PnPList -Title $Library -Template DocumentLibrary -Url $Library.Replace(" ", "") 
        Write-Host "Documentbibliotheek '$Library' succesvol aangemaakt." -ForegroundColor Green
    }
    catch {
        Write-Host "Fout bij het aanmaken van '$Library': $_" -ForegroundColor Red
    }
}

# Verbinding verbreken
Disconnect-PnPOnline

Write-Host "Script voltooid."
