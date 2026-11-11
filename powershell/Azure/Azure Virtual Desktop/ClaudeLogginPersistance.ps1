# Claude Desktop - FSLogix roaming workaround
# Uitvoeren onder het account van de betreffende gebruiker

$Folders = @(
    "$env:APPDATA\Claude",
    "$env:APPDATA\Claude-3p"
)

foreach ($Folder in $Folders) {
    if (-not (Test-Path -LiteralPath $Folder)) {
        New-Item -Path $Folder -ItemType Directory -Force |
            Out-Null

        Write-Host "Aangemaakt: $Folder" -ForegroundColor Green
    }
    else {
        Write-Host "Bestaat al: $Folder" -ForegroundColor Yellow
    }
}

Write-Host "`nClaude-profielmappen zijn gereed." -ForegroundColor Green