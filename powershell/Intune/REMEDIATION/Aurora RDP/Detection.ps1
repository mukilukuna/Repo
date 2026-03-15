# Intune Proactive Remediation - Detection
# Exit 1 = remediation nodig (1 of beide items bestaan)
# Exit 0 = compliant (beide bestaan niet)

$ShortcutPath = "C:\Users\Public\Desktop\Verhoeve Online Werkplek.lnk"
$FolderPath   = "C:\ITS\RDS"

$shortcutExists = Test-Path -LiteralPath $ShortcutPath
$folderExists   = Test-Path -LiteralPath $FolderPath

if ($shortcutExists -or $folderExists) {
    exit 1
}

exit 0
