<#
.SYNOPSIS
    Voegt Exchange Online-aliassen toe of verwijdert secundaire aliassen per domein.

.DESCRIPTION
    Zonder -Apply worden alleen de geplande wijzigingen getoond. Primaire SMTP-adressen
    worden bij RemoveDomain nooit verwijderd.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    [Parameter(Mandatory)]
    [ValidateSet('AddSingle', 'AddDomain', 'RemoveDomain')]
    [string]$Action,

    [string]$Mailbox,

    [string]$Alias,

    [string[]]$SourceDomain,

    [string]$TargetDomain,

    [string]$Domain,

    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$ModuleName = 'ExchangeOnlineManagement'

if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
    Write-Host "Module '$ModuleName' wordt geïnstalleerd..." -ForegroundColor Yellow
    Install-Module -Name $ModuleName -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
}
Import-Module -Name $ModuleName -ErrorAction Stop
$CallingCmdlet = $PSCmdlet

function Normalize-Domain {
    param([string]$Value)
    return $Value.Trim().TrimStart('@').ToLowerInvariant()
}

function Invoke-MailboxAliasChange {
    param (
        [Parameter(Mandatory)][string]$Identity,
        [Parameter(Mandatory)][ValidateSet('Add', 'Remove')][string]$Operation,
        [Parameter(Mandatory)][string]$Address
    )

    $Description = "$Operation alias $Address"
    if (-not $Apply) {
        Write-Host "[Voorbeeld] ${Identity}: $Description" -ForegroundColor Yellow
        return
    }

    if ($CallingCmdlet.ShouldProcess($Identity, $Description)) {
        if ($Operation -eq 'Add') {
            Set-Mailbox -Identity $Identity -EmailAddresses @{ Add = $Address } -ErrorAction Stop
        }
        else {
            Set-Mailbox -Identity $Identity -EmailAddresses @{ Remove = $Address } -ErrorAction Stop
        }
        Write-Host "${Identity}: $Description voltooid." -ForegroundColor Green
    }
}

switch ($Action) {
    'AddSingle' {
        if ([string]::IsNullOrWhiteSpace($Mailbox) -or [string]::IsNullOrWhiteSpace($Alias)) {
            throw 'Mailbox en Alias zijn verplicht bij Action AddSingle.'
        }
    }
    'AddDomain' {
        if (-not $SourceDomain -or [string]::IsNullOrWhiteSpace($TargetDomain)) {
            throw 'SourceDomain en TargetDomain zijn verplicht bij Action AddDomain.'
        }
    }
    'RemoveDomain' {
        if ([string]::IsNullOrWhiteSpace($Domain)) {
            throw 'Domain is verplicht bij Action RemoveDomain.'
        }
    }
}

Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop

if ($Action -eq 'AddSingle') {
    Invoke-MailboxAliasChange -Identity $Mailbox -Operation Add -Address $Alias
    return
}

$Mailboxes = @(
    Get-EXOMailbox -ResultSize Unlimited -Properties EmailAddresses, PrimarySmtpAddress, UserPrincipalName -ErrorAction Stop
)

if ($Action -eq 'AddDomain') {
    $SourceDomains = @($SourceDomain | ForEach-Object { Normalize-Domain $_ })
    $NormalizedTargetDomain = Normalize-Domain $TargetDomain

    foreach ($CurrentMailbox in $Mailboxes) {
        $PrimaryAddress = [string]$CurrentMailbox.PrimarySmtpAddress
        $PrimaryParts = $PrimaryAddress.Split('@')
        if ($PrimaryParts.Count -ne 2 -or $PrimaryParts[1].ToLowerInvariant() -notin $SourceDomains) {
            continue
        }

        $NewAlias = "$($PrimaryParts[0])@$NormalizedTargetDomain"
        $ExistingAddresses = @($CurrentMailbox.EmailAddresses | ForEach-Object { ([string]$_) -replace '^[sS][mM][tT][pP]:', '' })
        if ($ExistingAddresses -contains $NewAlias) {
            Write-Host "Overgeslagen; alias bestaat al: $NewAlias" -ForegroundColor DarkYellow
            continue
        }

        Invoke-MailboxAliasChange -Identity $CurrentMailbox.UserPrincipalName -Operation Add -Address $NewAlias
    }
    return
}

$NormalizedDomain = Normalize-Domain $Domain
foreach ($CurrentMailbox in $Mailboxes) {
    $SecondaryAliases = @(
        $CurrentMailbox.EmailAddresses |
            ForEach-Object { [string]$_ } |
            Where-Object { $_ -clike 'smtp:*' -and $_.Substring(5) -like "*@$NormalizedDomain" }
    )

    foreach ($SecondaryAlias in $SecondaryAliases) {
        Invoke-MailboxAliasChange -Identity $CurrentMailbox.UserPrincipalName -Operation Remove -Address $SecondaryAlias
    }
}
