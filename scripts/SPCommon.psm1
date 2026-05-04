<#
.SYNOPSIS
    SPCommon — Shared functions for the Mittelstand AD Toolkit.

.DESCRIPTION
    Provides logging, configuration loading, password generation,
    audit-log writing, and email helpers used by every script
    in the toolkit.

.NOTES
    Author : Mittelstand AD Toolkit
    Version: 1.0.0
#>

# ---------------------------------------------------------------------------
# Configuration loading
# ---------------------------------------------------------------------------
function Import-SPConfig {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\config.psd1')
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found at: $ConfigPath"
    }

    $config = Import-PowerShellDataFile -Path $ConfigPath
    Write-Verbose "Loaded configuration for company: $($config.Company.Name)"
    return $config
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Write-SPLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'AUDIT', 'DEBUG')]
        [string]$Level = 'INFO',
        [string]$LogFile,
        [string]$Component = 'SPCommon'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $user      = "$env:USERDOMAIN\$env:USERNAME"
    $line      = "[$timestamp] [$Level] [$Component] [$user] $Message"

    # Console output with color
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'AUDIT' { Write-Host $line -ForegroundColor Cyan }
        'DEBUG' { Write-Host $line -ForegroundColor Gray }
        default { Write-Host $line -ForegroundColor Green }
    }

    # File output
    if ($LogFile) {
        $logDir = Split-Path -Path $LogFile -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    }
}

# ---------------------------------------------------------------------------
# Password generation
# ---------------------------------------------------------------------------
function New-SPSecurePassword {
    [CmdletBinding()]
    param(
        [int]$Length = 14
    )

    # Character pools (excluding visually ambiguous characters: 0, O, l, 1, I)
    $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'.ToCharArray()
    $lower   = 'abcdefghjkmnpqrstuvwxyz'.ToCharArray()
    $digits  = '23456789'.ToCharArray()
    $special = '!#$%&*+-=?@'.ToCharArray()

    # Guarantee at least one of each type
    $password = @(
        ($upper   | Get-Random)
        ($lower   | Get-Random)
        ($digits  | Get-Random)
        ($special | Get-Random)
    )

    $allChars = $upper + $lower + $digits + $special
    for ($i = $password.Count; $i -lt $Length; $i++) {
        $password += ($allChars | Get-Random)
    }

    # Shuffle
    -join ($password | Sort-Object { Get-Random })
}

# ---------------------------------------------------------------------------
# Audit log entry (DSGVO-relevant changes)
# ---------------------------------------------------------------------------
function Write-SPAuditEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Action,
        [Parameter(Mandatory)] [string]$Target,
        [string]$Details,
        [string]$TicketId,
        [string]$AuditLogPath
    )

    $entry = [PSCustomObject]@{
        Timestamp   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffK')
        Operator    = "$env:USERDOMAIN\$env:USERNAME"
        Workstation = $env:COMPUTERNAME
        Action      = $Action
        Target      = $Target
        TicketId    = $TicketId
        Details     = $Details
    }

    if ($AuditLogPath) {
        $logDir = Split-Path -Path $AuditLogPath -Parent
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        $entry | Export-Csv -Path $AuditLogPath -Append -NoTypeInformation -Encoding UTF8
    }

    Write-SPLog -Message "AUDIT: $Action on $Target (Ticket: $TicketId)" -Level AUDIT
    return $entry
}

# ---------------------------------------------------------------------------
# Username generation (firstname.lastname, with collision handling)
# ---------------------------------------------------------------------------
function New-SPUsername {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$GivenName,
        [Parameter(Mandatory)] [string]$Surname
    )

    # Strip umlauts and special characters (German-specific)
    $umlautMap = @{
        'ä' = 'ae'; 'ö' = 'oe'; 'ü' = 'ue'; 'ß' = 'ss'
        'Ä' = 'Ae'; 'Ö' = 'Oe'; 'Ü' = 'Ue'
        'á' = 'a';  'é' = 'e';  'í' = 'i';  'ó' = 'o';  'ú' = 'u'
        'à' = 'a';  'è' = 'e';  'ì' = 'i';  'ò' = 'o';  'ù' = 'u'
    }

    $cleanGiven = $GivenName.ToLower()
    $cleanSurn  = $Surname.ToLower()
    foreach ($key in $umlautMap.Keys) {
        $cleanGiven = $cleanGiven -replace $key, $umlautMap[$key]
        $cleanSurn  = $cleanSurn  -replace $key, $umlautMap[$key]
    }

    # Remove anything not a-z
    $cleanGiven = $cleanGiven -replace '[^a-z]', ''
    $cleanSurn  = $cleanSurn  -replace '[^a-z]', ''

    $base = "$cleanGiven.$cleanSurn"

    # Check for AD collision and append number if needed
    $candidate = $base
    $counter   = 1
    while (Get-ADUser -Filter "SamAccountName -eq '$candidate'" -ErrorAction SilentlyContinue) {
        $counter++
        $candidate = "$base$counter"
    }

    return $candidate
}

# ---------------------------------------------------------------------------
# Send email helper
# ---------------------------------------------------------------------------
function Send-SPMail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]]$To,
        [Parameter(Mandatory)] [string]$Subject,
        [Parameter(Mandatory)] [string]$Body,
        [string]$Attachment,
        [hashtable]$EmailConfig,
        [switch]$BodyAsHtml
    )

    $params = @{
        To         = $To
        From       = $EmailConfig.From
        Subject    = $Subject
        Body       = $Body
        SmtpServer = $EmailConfig.SmtpServer
        Port       = $EmailConfig.Port
        Encoding   = [System.Text.Encoding]::UTF8
    }

    if ($EmailConfig.UseSSL) { $params.UseSsl = $true }
    if ($BodyAsHtml)         { $params.BodyAsHtml = $true }
    if ($Attachment -and (Test-Path $Attachment)) { $params.Attachments = $Attachment }

    try {
        Send-MailMessage @params -ErrorAction Stop
        Write-SPLog -Message "Email sent to $($To -join ', '): $Subject" -Level INFO
    }
    catch {
        Write-SPLog -Message "Failed to send email: $_" -Level ERROR
        throw
    }
}

# ---------------------------------------------------------------------------
# Validate prerequisites (AD module, RSAT, permissions)
# ---------------------------------------------------------------------------
function Test-SPPrerequisites {
    [CmdletBinding()]
    param()

    $issues = @()

    # PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        $issues += "PowerShell 5.1 or later required (current: $($PSVersionTable.PSVersion))"
    }

    # ActiveDirectory module
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        $issues += "ActiveDirectory PowerShell module not found. Install RSAT-AD-PowerShell."
    }

    # Domain reachability
    try {
        $null = Get-ADDomain -ErrorAction Stop
    }
    catch {
        $issues += "Cannot contact Active Directory domain: $_"
    }

    if ($issues.Count -gt 0) {
        foreach ($issue in $issues) {
            Write-SPLog -Message $issue -Level ERROR
        }
        return $false
    }

    return $true
}

Export-ModuleMember -Function @(
    'Import-SPConfig',
    'Write-SPLog',
    'New-SPSecurePassword',
    'Write-SPAuditEntry',
    'New-SPUsername',
    'Send-SPMail',
    'Test-SPPrerequisites'
)
