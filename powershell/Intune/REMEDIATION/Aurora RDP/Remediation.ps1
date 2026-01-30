# Intune Proactive Remediation - Remediation
# Verwijdert shortcut en map (incl. inhoud)
# Exit 0 = verwijderd of bestond al niet / na afloop is het weg
# Exit 1 = na poging bestaat er nog iets

$ShortcutPath = "C:\Users\Public\Desktop\Verhoeve Online Werkplek.lnk"
$FolderPath   = "C:\ITS\RDS"

function Remove-ItemSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [switch]$IsFolder
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        if ($IsFolder) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        } else {
            Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
        }
    } catch {
        # Laat remediations doorlopen, maar exitcode bepalen we onderaan
    }
}

# Verwijderen
Remove-ItemSafe -Path $ShortcutPath
Remove-ItemSafe -Path $FolderPath -IsFolder

# Controle achteraf
$shortcutExists = Test-Path -LiteralPath $ShortcutPath
$folderExists   = Test-Path -LiteralPath $FolderPath

if ($shortcutExists -or $folderExists) {
    exit 1
}

exit 0
