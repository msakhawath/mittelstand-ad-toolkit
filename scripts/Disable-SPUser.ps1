<#
.SYNOPSIS
    Performs a standardized AD offboarding workflow.

.DESCRIPTION
    Disables a user account, moves it to the "Disabled Users" OU, removes
    it from all security groups (preserving a record), sets a description
    with offboarding metadata, and writes a full audit trail. This script
    is DSGVO-compliant: no immediate deletion, but a clean audit log.

.PARAMETER Username
    SamAccountName of the user to offboard.

.PARAMETER CsvPath
    Alternative: path to a CSV with columns Username, LastDay, Reason, TicketId.

.PARAMETER TicketId
    Helpdesk ticket ID for audit purposes.

.PARAMETER Reason
    Reason for offboarding (Resignation, Termination, EndOfContract, etc.)

.PARAMETER LastDay
    Last working day (YYYY-MM-DD).

.PARAMETER WhatIf
    Show what would happen without making changes.

.EXAMPLE
    .\Disable-SPUser.ps1 -Username max.mustermann -TicketId TKT-2026-0042 -Reason Resignation -LastDay 2026-05-31

.EXAMPLE
    .\Disable-SPUser.ps1 -CsvPath .\examples\leavers-2026-01.csv

.NOTES
    Author : Mittelstand AD Toolkit
    Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Single')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Single')]
    [string]$Username,

    [Parameter(Mandatory, ParameterSetName = 'Bulk')]
    [ValidateScript({ Test-Path $_ })]
    [string]$CsvPath,

    [Parameter(ParameterSetName = 'Single')]
    [string]$TicketId,

    [Parameter(ParameterSetName = 'Single')]
    [ValidateSet('Resignation', 'Termination', 'EndOfContract', 'Retirement', 'Other')]
    [string]$Reason = 'Resignation',

    [Parameter(ParameterSetName = 'Single')]
    [string]$LastDay = (Get-Date -Format 'yyyy-MM-dd'),

    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\config.psd1')
)

# --- Setup -------------------------------------------------------------------
Import-Module (Join-Path $PSScriptRoot 'SPCommon.psm1') -Force
Import-Module ActiveDirectory -ErrorAction Stop

$config    = Import-SPConfig -ConfigPath $ConfigPath
$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$logFile   = Join-Path $config.Paths.LogDirectory "Offboarding_$timestamp.log"
$auditLog  = Join-Path $config.Paths.LogDirectory "Audit_Offboarding.csv"

Write-SPLog -Message "=== Offboarding script started ===" -Level INFO -LogFile $logFile -Component 'Disable-SPUser'

if (-not (Test-SPPrerequisites)) {
    Write-SPLog -Message "Prerequisites failed. Exiting." -Level ERROR -LogFile $logFile
    exit 1
}

# --- Build leaver list -------------------------------------------------------
if ($PSCmdlet.ParameterSetName -eq 'Bulk') {
    $leavers = Import-Csv -Path $CsvPath -Delimiter ';' -Encoding UTF8
}
else {
    $leavers = @([PSCustomObject]@{
        Username = $Username
        LastDay  = $LastDay
        Reason   = $Reason
        TicketId = $TicketId
    })
}

# --- Process each leaver -----------------------------------------------------
$processed = 0
$failed    = 0

foreach ($leaver in $leavers) {
    Write-SPLog -Message "--- Processing $($leaver.Username) ---" -Level INFO -LogFile $logFile

    try {
        # --- Find the user ---
        $user = Get-ADUser -Identity $leaver.Username `
                           -Properties MemberOf, Description, EmailAddress, Manager `
                           -ErrorAction Stop

        # --- Capture state before change (for audit) ---
        $originalGroups = @($user.MemberOf | ForEach-Object {
            (Get-ADGroup -Identity $_ -ErrorAction SilentlyContinue).Name
        } | Where-Object { $_ })

        $originalState = [PSCustomObject]@{
            Username    = $user.SamAccountName
            DisplayName = $user.Name
            Email       = $user.EmailAddress
            DN          = $user.DistinguishedName
            Groups      = ($originalGroups -join ', ')
            DisabledOn  = $timestamp
            LastDay     = $leaver.LastDay
            Reason      = $leaver.Reason
            TicketId    = $leaver.TicketId
            ProcessedBy = "$env:USERDOMAIN\$env:USERNAME"
        }

        # Save state to archive for restore-if-needed
        $archiveDir  = $config.Paths.ArchivePath
        $archiveFile = Join-Path $archiveDir "$($user.SamAccountName)_$timestamp.json"
        if ($PSCmdlet.ShouldProcess($archiveFile, 'Archive original user state')) {
            if (-not (Test-Path $archiveDir)) {
                New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null
            }
            $originalState | ConvertTo-Json -Depth 5 | Out-File -FilePath $archiveFile -Encoding UTF8
            Write-SPLog -Message "Archived state to: $archiveFile" -Level INFO -LogFile $logFile
        }

        # --- Step 1: Disable account ---
        if ($PSCmdlet.ShouldProcess($user.SamAccountName, 'Disable account')) {
            Disable-ADAccount -Identity $user -ErrorAction Stop
            Write-SPLog -Message "Disabled account: $($user.SamAccountName)" -Level INFO -LogFile $logFile
        }

        # --- Step 2: Update description with offboarding metadata ---
        $newDesc = "DISABLED $timestamp by $env:USERNAME | Ticket: $($leaver.TicketId) | Reason: $($leaver.Reason) | LastDay: $($leaver.LastDay)"
        if ($PSCmdlet.ShouldProcess($user.SamAccountName, 'Update description')) {
            Set-ADUser -Identity $user -Description $newDesc -ErrorAction Stop
        }

        # --- Step 3: Reset password to a long random string ---
        $randomPwd = New-SPSecurePassword -Length 32
        $securePwd = ConvertTo-SecureString -String $randomPwd -AsPlainText -Force
        if ($PSCmdlet.ShouldProcess($user.SamAccountName, 'Reset password')) {
            Set-ADAccountPassword -Identity $user -Reset -NewPassword $securePwd -ErrorAction Stop
            Write-SPLog -Message "Password randomized for: $($user.SamAccountName)" -Level INFO -LogFile $logFile
        }

        # --- Step 4: Remove from all groups (except Domain Users) ---
        foreach ($groupDN in $user.MemberOf) {
            $group = Get-ADGroup -Identity $groupDN -ErrorAction SilentlyContinue
            if ($group -and $group.Name -ne 'Domain Users') {
                if ($PSCmdlet.ShouldProcess($user.SamAccountName, "Remove from $($group.Name)")) {
                    try {
                        Remove-ADGroupMember -Identity $group -Members $user -Confirm:$false -ErrorAction Stop
                        Write-SPLog -Message "Removed $($user.SamAccountName) from $($group.Name)" -Level INFO -LogFile $logFile
                    }
                    catch {
                        Write-SPLog -Message "Could not remove from $($group.Name): $_" -Level WARN -LogFile $logFile
                    }
                }
            }
        }

        # --- Step 5: Move to Disabled Users OU ---
        if ($PSCmdlet.ShouldProcess($user.SamAccountName, "Move to $($config.OUs.DisabledUsers)")) {
            Move-ADObject -Identity $user.DistinguishedName -TargetPath $config.OUs.DisabledUsers -ErrorAction Stop
            Write-SPLog -Message "Moved $($user.SamAccountName) to disabled OU." -Level INFO -LogFile $logFile
        }

        # --- Step 6: Audit entry ---
        Write-SPAuditEntry -Action 'USER_DISABLED' `
                          -Target $user.SamAccountName `
                          -Details "Reason=$($leaver.Reason); LastDay=$($leaver.LastDay); GroupsRemoved=$($originalGroups.Count); Archive=$archiveFile" `
                          -TicketId $leaver.TicketId `
                          -AuditLogPath $auditLog | Out-Null

        # --- Step 7: Notify HR & manager ---
        if (-not $WhatIfPreference -and $config.Email.SmtpServer) {
            $managerEmail = $null
            if ($user.Manager) {
                $mgr = Get-ADUser -Identity $user.Manager -Properties EmailAddress -ErrorAction SilentlyContinue
                $managerEmail = $mgr.EmailAddress
            }

            $recipients = @($config.Email.HRTeam, $config.Email.ITTeam)
            if ($managerEmail) { $recipients += $managerEmail }

            $body = @(
                'Offboarding abgeschlossen / Offboarding completed',
                '',
                "Benutzer / User:    $($user.Name) ($($user.SamAccountName))",
                "Letzter Tag / Last day: $($leaver.LastDay)",
                "Grund / Reason:     $($leaver.Reason)",
                "Ticket:             $($leaver.TicketId)",
                "Verarbeitet von / Processed by: $env:USERNAME",
                '',
                'Status:',
                '  ✓ Account deaktiviert / Account disabled',
                '  ✓ Aus allen Gruppen entfernt / Removed from all groups',
                '  ✓ In Disabled-OU verschoben / Moved to Disabled OU',
                '  ✓ Passwort randomisiert / Password randomized',
                '',
                "Archiv: $archiveFile"
            ) -join [Environment]::NewLine
            try {
                Send-SPMail -To $recipients `
                            -Subject "[Offboarding] $($user.Name) — $($leaver.LastDay)" `
                            -Body $body `
                            -EmailConfig $config.Email
            }
            catch {
                Write-SPLog -Message "Notification email failed: $_" -Level WARN -LogFile $logFile
            }
        }

        $processed++
    }
    catch {
        Write-SPLog -Message "Failed to offboard $($leaver.Username): $_" -Level ERROR -LogFile $logFile
        $failed++
    }
}

Write-SPLog -Message "=== Summary: $processed processed, $failed failed ===" -Level INFO -LogFile $logFile
Write-SPLog -Message "=== Offboarding script finished ===" -Level INFO -LogFile $logFile
