<#
.SYNOPSIS
    Bootstraps the OU structure and default groups for Schmidt & Partner GmbH.

.DESCRIPTION
    Creates the entire OU hierarchy and default security groups defined in
    config.psd1. Idempotent: safe to run multiple times.

.EXAMPLE
    .\Initialize-SPOUStructure.ps1 -WhatIf

.EXAMPLE
    .\Initialize-SPOUStructure.ps1

.NOTES
    Run ONCE during initial lab setup, then refer to docs/02-ou-structure.md.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\config.psd1')
)

Import-Module (Join-Path $PSScriptRoot 'SPCommon.psm1') -Force
Import-Module ActiveDirectory -ErrorAction Stop

$config    = Import-SPConfig -ConfigPath $ConfigPath
$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$logFile   = Join-Path $config.Paths.LogDirectory "OUInit_$timestamp.log"

Write-SPLog -Message "=== OU initialization started ===" -Level INFO -LogFile $logFile

if (-not (Test-SPPrerequisites)) { exit 1 }

$domainDN = (Get-ADDomain).DistinguishedName

# --- Create root OU ---
function New-OUIfMissing {
    param(
        [string]$Name,
        [string]$ParentDN,
        [string]$Description
    )

    $fullDN = "OU=$Name,$ParentDN"
    $existing = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$fullDN'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-SPLog -Message "OU exists: $fullDN" -Level INFO -LogFile $logFile
        return
    }

    if ($PSCmdlet.ShouldProcess($fullDN, 'Create OU')) {
        New-ADOrganizationalUnit -Name $Name -Path $ParentDN -Description $Description -ProtectedFromAccidentalDeletion $true
        Write-SPLog -Message "Created OU: $fullDN" -Level INFO -LogFile $logFile
    }
}

# Build hierarchy
New-OUIfMissing -Name 'SchmidtPartner' -ParentDN $domainDN -Description 'Root OU for Schmidt & Partner GmbH'

$rootDN = $config.OUs.Root
New-OUIfMissing -Name 'Users'           -ParentDN $rootDN -Description 'All employee user objects'
New-OUIfMissing -Name 'ServiceAccounts' -ParentDN $rootDN -Description 'Service accounts (no interactive logon)'
New-OUIfMissing -Name 'Computers'       -ParentDN $rootDN -Description 'Workstations and servers'
New-OUIfMissing -Name 'Groups'          -ParentDN $rootDN -Description 'Security and distribution groups'

$usersDN = $config.OUs.Users
New-OUIfMissing -Name 'Disabled' -ParentDN $usersDN -Description 'Disabled / offboarded users'

# Department OUs
foreach ($dept in $config.OUs.Departments.Keys) {
    New-OUIfMissing -Name $dept -ParentDN $usersDN -Description "$dept department users"
}

# --- Create default groups ---
$groupsOU = $config.OUs.Groups
$allGroups = $config.DepartmentGroups.Values | ForEach-Object { $_ } | Sort-Object -Unique

foreach ($groupName in $allGroups) {
    $existing = Get-ADGroup -Filter "SamAccountName -eq '$groupName'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-SPLog -Message "Group exists: $groupName" -Level INFO -LogFile $logFile
        continue
    }

    if ($PSCmdlet.ShouldProcess($groupName, 'Create global security group')) {
        New-ADGroup -Name $groupName `
                    -SamAccountName $groupName `
                    -GroupScope Global `
                    -GroupCategory Security `
                    -Path $groupsOU `
                    -Description "Auto-created by AD Toolkit"
        Write-SPLog -Message "Created group: $groupName" -Level INFO -LogFile $logFile
    }
}

Write-SPLog -Message "=== OU initialization finished ===" -Level INFO -LogFile $logFile
Write-Host "`n✓ OU structure initialized. See docs/02-ou-structure.md for the design rationale.`n" -ForegroundColor Green
