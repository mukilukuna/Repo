# Run in user-context
# Driveletters zijn per gebruiker

$maps = @(
  @{L='G'; U='\\FILESERVER01\Share01'},
  @{L='I'; U='\\FILESERVER01\Share02'},
  @{L='J'; U='\\FILESERVER01\Share03'},
  @{L='K'; U='\\FILESERVER01\Share04'},
  @{L='L'; U='\\FILESERVER01\Share05'},
  @{L='M'; U='\\FILESERVER01\Share06'},
  @{L='N'; U='\\FILESERVER01\Share07'},
  @{L='O'; U='\\FILESERVER01\Share08'},
  @{L='P'; U='\\FILESERVER01\Share09'},
  @{L='R'; U='\\FILESERVER01\Share08\Subfolder01'},
  @{L='S'; U='\\FILESERVER02\Share10'},
  @{L='U'; U='\\FILESERVER01\Share08\Subfolder02'},
  @{L='V'; U='\\FILESERVER01\Share08\Subfolder03'},
  @{L='W'; U='\\FILESERVER01\Share08\Subfolder04'},
  @{L='X'; U='\\FILESERVER01\Share11'},
  @{L='Y'; U='\\192.168.1.250\Share12'}
)

foreach ($m in $maps) {
  $letter = $m.L.ToUpper()
  $drive  = "$letter`:"

  # Sla over als de driveletter al in gebruik is
  if (Get-PSDrive -Name $letter -ErrorAction SilentlyContinue) {
    continue
  }

  # Probeer mapping; wacht maximaal 4 seconden en stop het proces als het blijft hangen
  $cmd = "/c net use $drive $($m.U) /persistent:yes >nul 2>&1"
  $p = Start-Process cmd.exe -ArgumentList $cmd -WindowStyle Hidden -PassThru

  if (-not $p.WaitForExit(4000)) {
    try {
      $p.Kill()
    }
    catch {}
  }
}

# Marker-bestand
$flagDir = Join-Path $env:LOCALAPPDATA 'CompanyName'
$flag    = Join-Path $flagDir 'NetDrivesInstalled.txt'

New-Item -ItemType Directory -Path $flagDir -Force | Out-Null

# Leeg bestand, alleen bestaan telt
New-Item -ItemType File -Path $flag -Force | Out-Null

# Alternatief met tijdstempel:
# "Net drives mapped at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -Path $flag -Encoding utf8