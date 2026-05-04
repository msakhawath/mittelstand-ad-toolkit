<#
.SYNOPSIS
    Helpdesk-friendly password reset with full audit logging.

.DESCRIPTION
    Generates a secure temporary password, resets the user's AD password,
    forces a change at next logon, unlocks the account if needed, and
    writes a tamper-evident audit log entry. Designed to be the ONLY way
    helpdesk staff reset passwords — to ensure consistent logging.

.PARAMETER Username
    SamAccountName of the user.

.PARAMETER TicketId
    Helpdesk ticket ID (mandatory — for audit trail).

.PARAMETER UnlockOnly
    Only unlock the account, do not reset the password.

.PARAMETER NoChangeAtLogon
    Don't force change at next logon (rarely needed; not recommended).

.EXAMPLE
    .\Reset-SPPassword.ps1 -Username max.mustermann -TicketId TKT-2026-0123

.EXAMPLE
    .\Reset-SPPassword.ps1 -Username max.mustermann -TicketId TKT-2026-0123 -UnlockOnly

.NOTES
    Author : Mittelstand AD Toolkit
    Version: 1.0.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Username,

    [Parameter(Mandatory)]
    [ValidatePattern('^TKT-\d{4}-\d{4,}$')]
    [string]$TicketId,

    [switch]$UnlockOnly,
    [switch]$NoChangeAtLogon,

    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\config.psd1')
)

# --- Setup -------------------------------------------------------------------
Import-Module (Join-Path $PSScriptRoot 'SPCommon.psm1') -Force
Import-Module ActiveDirectory -ErrorAction Stop

$config    = Import-SPConfig -ConfigPath $ConfigPath
$timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$logFile   = Join-Path $config.Paths.LogDirectory "PasswordReset_$timestamp.log"
$auditLog  = Join-Path $config.Paths.LogDirectory "Audit_PasswordReset.csv"

Write-SPLog -Message "=== Password reset started for $Username (Ticket: $TicketId) ===" -Level INFO -LogFile $logFile -Component 'Reset-SPPassword'

if (-not (Test-SPPrerequisites)) { exit 1 }

# --- Find user ---------------------------------------------------------------
try {
    $user = Get-ADUser -Identity $Username -Properties LockedOut, Enabled, EmailAddress -ErrorAction Stop
}
catch {
    Write-SPLog -Message "User not found: $Username" -Level ERROR -LogFile $logFile
    exit 1
}

if (-not $user.Enabled) {
    Write-SPLog -Message "User $Username is DISABLED. Reset aborted." -Level ERROR -LogFile $logFile
    Write-Host "`n  ⚠ User is disabled. Cannot reset password." -ForegroundColor Red
    exit 1
}

# --- Unlock if needed --------------------------------------------------------
if ($user.LockedOut) {
    if ($PSCmdlet.ShouldProcess($Username, 'Unlock account')) {
        Unlock-ADAccount -Identity $user
        Write-SPLog -Message "Account unlocked: $Username" -Level INFO -LogFile $logFile

        Write-SPAuditEntry -Action 'ACCOUNT_UNLOCKED' `
                          -Target $Username `
                          -TicketId $TicketId `
                          -AuditLogPath $auditLog | Out-Null
    }
}
else {
    Write-SPLog -Message "Account was not locked." -Level INFO -LogFile $logFile
}

# --- Unlock-only mode --------------------------------------------------------
if ($UnlockOnly) {
    Write-SPLog -Message "UnlockOnly mode — password unchanged." -Level INFO -LogFile $logFile
    Write-Host "`n  ✓ Account unlocked for $Username." -ForegroundColor Green
    exit 0
}

# --- Reset password ----------------------------------------------------------
$newPassword = New-SPSecurePassword -Length 14
$securePwd   = ConvertTo-SecureString -String $newPassword -AsPlainText -Force

if ($PSCmdlet.ShouldProcess($Username, 'Reset password')) {
    try {
        Set-ADAccountPassword -Identity $user -Reset -NewPassword $securePwd -ErrorAction Stop
        Write-SPLog -Message "Password reset for: $Username" -Level INFO -LogFile $logFile

        if (-not $NoChangeAtLogon) {
            Set-ADUser -Identity $user -ChangePasswordAtLogon $true
            Write-SPLog -Message "Forced password change at next logon." -Level INFO -LogFile $logFile
        }

        Write-SPAuditEntry -Action 'PASSWORD_RESET' `
                          -Target $Username `
                          -Details "ChangeAtLogon=$(-not $NoChangeAtLogon)" `
                          -TicketId $TicketId `
                          -AuditLogPath $auditLog | Out-Null
    }
    catch {
        Write-SPLog -Message "Password reset FAILED for $Username : $_" -Level ERROR -LogFile $logFile
        exit 1
    }
}

# --- Display result ----------------------------------------------------------
Write-Host ""
Write-Host "  ╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║                  PASSWORD RESET SUCCESSFUL                 ║" -ForegroundColor Green
Write-Host "  ╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "    User:     $($user.Name) ($Username)" -ForegroundColor White
Write-Host "    Email:    $($user.EmailAddress)" -ForegroundColor White
Write-Host "    Ticket:   $TicketId" -ForegroundColor White
Write-Host ""
Write-Host "    Temporary Password: " -NoNewline
Write-Host $newPassword -ForegroundColor Yellow
Write-Host ""
Write-Host "  ⚠ Communicate this password to the user via a SECURE channel." -ForegroundColor Yellow
Write-Host "  ⚠ The user MUST change it at next logon." -ForegroundColor Yellow
Write-Host ""
Write-Host "  Audit log: $auditLog" -ForegroundColor Gray
Write-Host ""

Write-SPLog -Message "=== Password reset finished ===" -Level INFO -LogFile $logFile
