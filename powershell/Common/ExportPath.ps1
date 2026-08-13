function Resolve-ExportDirectory {
    [CmdletBinding()]
    param (
        [string]$Path,
        [string]$DefaultPath = 'C:\temp',
        [string]$Prompt = 'Exportmap'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Read-Host "$Prompt (druk op Enter voor '$DefaultPath')"
    }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $DefaultPath
    }

    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path -Path (Get-Location).ProviderPath -ChildPath $Path
    }

    $Path = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
    }
    elseif (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Het exportpad is geen map: $Path"
    }

    return $Path
}

function Resolve-ExportFilePath {
    [CmdletBinding()]
    param (
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$DefaultPath,
        [string]$Prompt = 'Exportbestand'
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Read-Host "$Prompt (druk op Enter voor '$DefaultPath')"
    }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $DefaultPath
    }

    $Path = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        $Path = Join-Path -Path (Get-Location).ProviderPath -ChildPath $Path
    }

    $Path = [System.IO.Path]::GetFullPath($Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        throw "Het exportpad verwijst naar een map; geef ook een bestandsnaam op: $Path"
    }

    $ParentPath = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $ParentPath)) {
        New-Item -ItemType Directory -Path $ParentPath -Force -ErrorAction Stop | Out-Null
    }

    return $Path
}
