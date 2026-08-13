#requires -Version 5.1

<#
.SYNOPSIS
    Maakt een rapport van mailbox- en archiefgroottes in Exchange Online.

.DESCRIPTION
    Verzamelt mailboxstatistieken van gebruikersmailboxen en gedeelde
    mailboxen en exporteert het resultaat automatisch naar C:\Temp.

    De Exchange Online-aanmelding wordt interactief geopend.
    Er hoeft geen AdminUPN vooraf te worden opgegeven.

.EXAMPLE
    .\Inventarisatie_MailboxSize.ps1

    Haalt gebruikersmailboxen en gedeelde mailboxen op, inclusief archieven.

.EXAMPLE
    .\Inventarisatie_MailboxSize.ps1 -SharedMailboxes only

    Haalt alleen gedeelde mailboxen op.

.EXAMPLE
    .\Inventarisatie_MailboxSize.ps1 -SharedMailboxes no

    Haalt alleen gebruikersmailboxen op.

.EXAMPLE
    .\Inventarisatie_MailboxSize.ps1 -Archive:$false

    Haalt mailboxgegevens op zonder archiefstatistieken.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory = $false)]
  [ValidateSet(
    'no',
    'only',
    'include'
  )]
  [string]$SharedMailboxes = 'include',

  [Parameter(Mandatory = $false)]
  [switch]$Archive = $true,

  [Parameter(Mandatory = $false)]
  [string]$ImportCSV,

  [Parameter(Mandatory = $false)]
  [string]$ExportDirectory
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..\..\Common\ExportPath.ps1')

# ============================================================
# Exportinstellingen
# ============================================================

$ExportFolder = Resolve-ExportDirectory -Path $ExportDirectory -DefaultPath 'C:\Temp' -Prompt 'Exportmap voor het mailboxgrootterapport'
$TimeStamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$CSVPath = Join-Path `
  -Path $ExportFolder `
  -ChildPath "MailboxSizeReport_$TimeStamp.csv"

# ============================================================
# Functies
# ============================================================

function Test-IsAdministrator {
  [CmdletBinding()]
  param()

  $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()

  $WindowsPrincipal = [Security.Principal.WindowsPrincipal]::new(
    $CurrentIdentity
  )

  return $WindowsPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
  )
}

function Connect-ToExchangeOnline {
  [CmdletBinding()]
  param()

  $ModuleName = 'ExchangeOnlineManagement'

  if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
    Write-Host ''
    Write-Host `
      'De Exchange Online PowerShell-module is niet geïnstalleerd.' `
      -ForegroundColor Yellow

    if (-not (Test-IsAdministrator)) {
      throw @'
De module ExchangeOnlineManagement ontbreekt.

Start PowerShell of PowerShell ISE als administrator.
De module wordt uitsluitend in de computercontext geïnstalleerd
met -Scope AllUsers.
'@
    }

    Write-Host `
      'ExchangeOnlineManagement wordt in de computercontext geïnstalleerd...' `
      -ForegroundColor Cyan

    [Net.ServicePointManager]::SecurityProtocol = `
      [Net.SecurityProtocolType]::Tls12

    Install-Module `
      -Name $ModuleName `
      -Repository PSGallery `
      -Scope AllUsers `
      -AllowClobber `
      -Force `
      -ErrorAction Stop
  }

  Import-Module `
    -Name $ModuleName `
    -ErrorAction Stop

  Write-Host ''
  Write-Host `
    'Het Microsoft-aanmeldvenster wordt geopend...' `
    -ForegroundColor Cyan

  Connect-ExchangeOnline `
    -ShowBanner:$false `
    -ErrorAction Stop
}

function Convert-ExchangeSizeToGB {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $false)]
    [AllowNull()]
    $Value
  )

  if ($null -eq $Value) {
    return $null
  }

  $Text = $Value.ToString().Trim()

  if (
    [string]::IsNullOrWhiteSpace($Text) -or
    $Text -eq 'Unlimited'
  ) {
    return $null
  }

  # Exchange retourneert doorgaans bijvoorbeeld:
  # 12.34 GB (13,250,000,000 bytes)
  #
  # Het aantal bytes is betrouwbaarder dan de weergegeven eenheid.
  if ($Text -match '\((?<Bytes>[\d\s,\.]+)\sbytes\)') {
    $ByteText = $Matches.Bytes -replace '[^\d]', ''

    if (-not [string]::IsNullOrWhiteSpace($ByteText)) {
      $Bytes = [decimal]$ByteText

      return [math]::Round(
        [double]($Bytes / 1GB),
        2,
        [MidpointRounding]::AwayFromZero
      )
    }
  }

  # Terugval wanneer het aantal bytes niet in de tekst staat.
  $DisplayValue = ($Text -split '\(')[0].Trim()

  if (
    $DisplayValue -notmatch
    '^(?<Number>[\d\.,]+)\s*(?<Unit>TB|GB|MB|KB|B)$'
  ) {
    return $null
  }

  $NumberText = $Matches.Number
  $Unit = $Matches.Unit.ToUpperInvariant()

  if (
    $NumberText.Contains(',') -and
    $NumberText.Contains('.')
  ) {
    if (
      $NumberText.LastIndexOf(',') -gt
      $NumberText.LastIndexOf('.')
    ) {
      $NumberText = $NumberText.Replace('.', '')
      $NumberText = $NumberText.Replace(',', '.')
    }
    else {
      $NumberText = $NumberText.Replace(',', '')
    }
  }
  elseif ($NumberText.Contains(',')) {
    $NumberText = $NumberText.Replace(',', '.')
  }

  $Number = 0.0

  $Parsed = [double]::TryParse(
    $NumberText,
    [System.Globalization.NumberStyles]::Any,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [ref]$Number
  )

  if (-not $Parsed) {
    return $null
  }

  switch ($Unit) {
    'TB' {
      $SizeInGB = $Number * 1024
    }

    'GB' {
      $SizeInGB = $Number
    }

    'MB' {
      $SizeInGB = $Number / 1024
    }

    'KB' {
      $SizeInGB = $Number / 1024 / 1024
    }

    'B' {
      $SizeInGB = $Number / 1GB
    }

    default {
      return $null
    }
  }

  return [math]::Round(
    $SizeInGB,
    2,
    [MidpointRounding]::AwayFromZero
  )
}

function Get-MailboxesForReport {
  [CmdletBinding()]
  param()

  $Properties = @(
    'IssueWarningQuota'
    'ProhibitSendReceiveQuota'
    'ArchiveQuota'
    'ArchiveWarningQuota'
    'ArchiveDatabase'
  )

  if (-not [string]::IsNullOrWhiteSpace($ImportCSV)) {
    if (-not (Test-Path -LiteralPath $ImportCSV)) {
      throw "Het importbestand bestaat niet: $ImportCSV"
    }

    Write-Host `
      "Mailboxen worden ingelezen uit: $ImportCSV" `
      -ForegroundColor Cyan

    $ImportedMailboxes = Import-Csv `
      -LiteralPath $ImportCSV

    foreach ($ImportedMailbox in $ImportedMailboxes) {
      $EmailAddress = $null

      foreach ($PossibleColumn in @(
          'EmailAddress'
          'Email Address'
          'PrimarySmtpAddress'
          'UserPrincipalName'
          'UPN'
        )) {
        if (
          $ImportedMailbox.PSObject.Properties.Name -contains
          $PossibleColumn
        ) {
          $EmailAddress = $ImportedMailbox.$PossibleColumn
          break
        }
      }

      if ([string]::IsNullOrWhiteSpace($EmailAddress)) {
        Write-Warning `
          'Een regel in het importbestand bevat geen herkenbaar e-mailadres.'

        continue
      }

      try {
        Get-EXOMailbox `
          -Identity $EmailAddress `
          -Properties $Properties `
          -ErrorAction Stop |
        Select-Object `
          UserPrincipalName,
        DisplayName,
        PrimarySmtpAddress,
        RecipientType,
        RecipientTypeDetails,
        IssueWarningQuota,
        ProhibitSendReceiveQuota,
        ArchiveQuota,
        ArchiveWarningQuota,
        ArchiveDatabase
      }
      catch {
        Write-Warning `
          "Mailbox $EmailAddress kon niet worden opgehaald: $($_.Exception.Message)"
      }
    }

    return
  }

  switch ($SharedMailboxes) {
    'include' {
      $MailboxTypes = @(
        'UserMailbox'
        'SharedMailbox'
      )
    }

    'only' {
      $MailboxTypes = @(
        'SharedMailbox'
      )
    }

    'no' {
      $MailboxTypes = @(
        'UserMailbox'
      )
    }
  }

  Get-EXOMailbox `
    -ResultSize Unlimited `
    -RecipientTypeDetails $MailboxTypes `
    -Properties $Properties `
    -ErrorAction Stop |
  Select-Object `
    UserPrincipalName,
  DisplayName,
  PrimarySmtpAddress,
  RecipientType,
  RecipientTypeDetails,
  IssueWarningQuota,
  ProhibitSendReceiveQuota,
  ArchiveQuota,
  ArchiveWarningQuota,
  ArchiveDatabase
}

function Get-MailboxSizeReport {
  [CmdletBinding()]
  param()

  $Mailboxes = @(
    Get-MailboxesForReport
  )

  if ($Mailboxes.Count -eq 0) {
    Write-Warning 'Er zijn geen mailboxen gevonden.'
    return
  }

  $CurrentNumber = 0

  foreach ($Mailbox in $Mailboxes) {
    $CurrentNumber++

    $PercentComplete = [math]::Round(
      ($CurrentNumber / $Mailboxes.Count) * 100,
      0
    )

    Write-Progress `
      -Activity 'Mailboxgegevens verzamelen' `
      -Status "$CurrentNumber van $($Mailboxes.Count)" `
      -PercentComplete $PercentComplete `
      -CurrentOperation $Mailbox.DisplayName

    try {
      # ========================================================
      # Primaire mailbox
      # ========================================================

      $MailboxStatistics = Get-EXOMailboxStatistics `
        -Identity $Mailbox.UserPrincipalName `
        -Properties LastUserActionTime `
        -ErrorAction Stop |
      Select-Object `
        TotalItemSize,
      TotalDeletedItemSize,
      ItemCount,
      DeletedItemCount,
      LastUserActionTime

      $TotalSizeGB = Convert-ExchangeSizeToGB `
        -Value $MailboxStatistics.TotalItemSize

      $DeletedItemsSizeGB = Convert-ExchangeSizeToGB `
        -Value $MailboxStatistics.TotalDeletedItemSize

      $WarningQuotaGB = Convert-ExchangeSizeToGB `
        -Value $Mailbox.IssueWarningQuota

      $MaximumMailboxSizeGB = Convert-ExchangeSizeToGB `
        -Value $Mailbox.ProhibitSendReceiveQuota

      if (
        $null -ne $MaximumMailboxSizeGB -and
        $null -ne $TotalSizeGB
      ) {
        $MailboxFreeSpaceGB = [math]::Round(
          $MaximumMailboxSizeGB - $TotalSizeGB,
          2,
          [MidpointRounding]::AwayFromZero
        )
      }
      else {
        $MailboxFreeSpaceGB = '-'
      }

      # ========================================================
      # Archiefmailbox
      # ========================================================

      $ArchiveStatistics = $null
      $ArchiveSizeGB = $null
      $ArchiveQuotaGB = $null
      $ArchiveWarningGB = $null
      $ArchiveFreeGB = '-'

      if (
        $Archive.IsPresent -and
        $null -ne $Mailbox.ArchiveDatabase
      ) {
        try {
          $ArchiveStatistics = Get-EXOMailboxStatistics `
            -Identity $Mailbox.UserPrincipalName `
            -Archive `
            -ErrorAction Stop |
          Select-Object `
            TotalItemSize,
          ItemCount,
          DeletedItemCount

          $ArchiveSizeGB = Convert-ExchangeSizeToGB `
            -Value $ArchiveStatistics.TotalItemSize

          $ArchiveQuotaGB = Convert-ExchangeSizeToGB `
            -Value $Mailbox.ArchiveQuota

          $ArchiveWarningGB = Convert-ExchangeSizeToGB `
            -Value $Mailbox.ArchiveWarningQuota

          if (
            $null -ne $ArchiveQuotaGB -and
            $null -ne $ArchiveSizeGB
          ) {
            $ArchiveFreeGB = [math]::Round(
              $ArchiveQuotaGB - $ArchiveSizeGB,
              2,
              [MidpointRounding]::AwayFromZero
            )
          }
        }
        catch {
          Write-Warning (
            "Archiefstatistieken konden niet worden opgehaald " +
            "voor $($Mailbox.UserPrincipalName): " +
            $_.Exception.Message
          )
        }
      }

      # ========================================================
      # Verzonden items
      # ========================================================

      $SentItemsStatistics = $null

      try {
        $SentItemsStatistics = Get-EXOMailboxFolderStatistics `
          -Identity $Mailbox.UserPrincipalName `
          -FolderScope SentItems `
          -ErrorAction Stop |
        Where-Object {
          $_.FolderType -eq 'SentItems' -or
          $_.FolderPath -in @(
            '/Sent Items'
            '/Verzonden items'
          )
        } |
        Select-Object `
          -First 1 `
          ItemsInFolderAndSubfolders,
        FolderAndSubfolderSize
      }
      catch {
        Write-Warning (
          "De map Verzonden items kon niet worden uitgelezen " +
          "voor $($Mailbox.UserPrincipalName)."
        )
      }

      if ($null -ne $SentItemsStatistics) {
        $SentItemsSizeGB = Convert-ExchangeSizeToGB `
          -Value $SentItemsStatistics.FolderAndSubfolderSize

        $SentItemsCount = `
          $SentItemsStatistics.ItemsInFolderAndSubfolders
      }
      else {
        $SentItemsSizeGB = '-'
        $SentItemsCount = '-'
      }

      # ========================================================
      # Rapportregel
      # ========================================================

      [PSCustomObject][ordered]@{
        'Display Name'                    = $Mailbox.DisplayName
        'Email Address'                   = $Mailbox.PrimarySmtpAddress.ToString()
        'Mailbox Type'                    = $Mailbox.RecipientTypeDetails
        'Last User Action Time'           = $MailboxStatistics.LastUserActionTime
        'Total Size (GB)'                 = $TotalSizeGB
        'Deleted Items Size (GB)'         = $DeletedItemsSizeGB
        'Item Count'                      = $MailboxStatistics.ItemCount
        'Deleted Items Count'             = $MailboxStatistics.DeletedItemCount
        'Mailbox Warning Quota (GB)'      = if ($null -ne $WarningQuotaGB) {
          $WarningQuotaGB
        }
        else {
          '-'
        }
        'Max Mailbox Size (GB)'           = if ($null -ne $MaximumMailboxSizeGB) {
          $MaximumMailboxSizeGB
        }
        else {
          '-'
        }
        'Mailbox Free Space (GB)'         = $MailboxFreeSpaceGB
        'Sent Items Size (GB)'            = $SentItemsSizeGB
        'Sent Items Count'                = $SentItemsCount
        'Archive Size (GB)'               = if ($null -ne $ArchiveSizeGB) {
          $ArchiveSizeGB
        }
        else {
          '-'
        }
        'Archive Items Count'             = if ($null -ne $ArchiveStatistics) {
          $ArchiveStatistics.ItemCount
        }
        else {
          '-'
        }
        'Archive Mailbox Free Space (GB)' = $ArchiveFreeGB
        'Archive Deleted Items Count'     = if ($null -ne $ArchiveStatistics) {
          $ArchiveStatistics.DeletedItemCount
        }
        else {
          '-'
        }
        'Archive Warning Quota (GB)'      = if ($null -ne $ArchiveWarningGB) {
          $ArchiveWarningGB
        }
        else {
          '-'
        }
        'Archive Quota (GB)'              = if ($null -ne $ArchiveQuotaGB) {
          $ArchiveQuotaGB
        }
        else {
          '-'
        }
      }
    }
    catch {
      Write-Warning (
        "Mailbox $($Mailbox.UserPrincipalName) kon niet worden " +
        "verwerkt: $($_.Exception.Message)"
      )
    }
  }

  Write-Progress `
    -Activity 'Mailboxgegevens verzamelen' `
    -Completed
}

# ============================================================
# Script uitvoeren
# ============================================================

$ConnectedToExchangeOnline = $false

try {
  if (-not (Test-Path -LiteralPath $ExportFolder)) {
    New-Item `
      -Path $ExportFolder `
      -ItemType Directory `
      -Force `
      -ErrorAction Stop |
    Out-Null
  }

  Connect-ToExchangeOnline
  $ConnectedToExchangeOnline = $true

  Write-Host ''
  Write-Host `
    'Het mailboxrapport wordt samengesteld...' `
    -ForegroundColor Cyan
  Write-Host ''

  $Report = @(
    Get-MailboxSizeReport
  )

  if ($Report.Count -eq 0) {
    throw 'Er zijn geen mailboxgegevens gevonden. Er is geen CSV aangemaakt.'
  }

  $Report |
  Sort-Object `
    'Mailbox Type',
  'Display Name' |
  Export-Csv `
    -LiteralPath $CSVPath `
    -Delimiter ';' `
    -NoTypeInformation `
    -Encoding UTF8 `
    -Force

  if (-not (Test-Path -LiteralPath $CSVPath)) {
    throw 'Het CSV-bestand is niet aangemaakt.'
  }

  $CSVFile = Get-Item `
    -LiteralPath $CSVPath `
    -ErrorAction Stop

  if ($CSVFile.Length -eq 0) {
    throw 'Het CSV-bestand is leeg aangemaakt.'
  }

  Write-Host ''
  Write-Host '============================================' -ForegroundColor Green
  Write-Host 'Mailboxrapport succesvol aangemaakt' -ForegroundColor Green
  Write-Host '============================================' -ForegroundColor Green
  Write-Host "Aantal mailboxen : $($Report.Count)"
  Write-Host "Exportbestand    : $CSVPath" -ForegroundColor Cyan
  Write-Host ''
}
catch {
  Write-Host ''
  Write-Host `
    'Het mailboxrapport kon niet worden aangemaakt.' `
    -ForegroundColor Red

  Write-Host `
    $_.Exception.Message `
    -ForegroundColor Red

  throw
}
finally {
  if ($ConnectedToExchangeOnline) {
    Disconnect-ExchangeOnline `
      -Confirm:$false `
      -ErrorAction SilentlyContinue
  }
}
